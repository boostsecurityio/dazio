# Installs or upgrades dazio for the current user on Windows, without elevation.
#
#   irm https://raw.githubusercontent.com/boostsecurityio/dazio/HEAD/install.ps1 | iex
#
# iex runs this in the caller's session: everything sits in one scriptblock so
# no variable or preference leaks into it, and errors throw, because `exit`
# would close the user's window. Windows PowerShell 5.1 is the floor. ASCII
# only: 5.1 reads a BOM-less script as the ANSI code page.
& {
  $ErrorActionPreference = 'Stop'
  # Windows PowerShell's progress bar slows Invoke-WebRequest tenfold.
  $ProgressPreference = 'SilentlyContinue'

  $repo = 'https://github.com/boostsecurityio/dazio'
  # The archives are built in the private monorepo and published here, so the
  # keyless signing identity names that repository's release workflow at the
  # tag it ran on.
  $workflow = 'https://github.com/boostsecurityio/boostfree-endpoint/.github/workflows/release-endpoint.yml'
  $oidcIssuer = 'https://token.actions.githubusercontent.com'

  function Fail($msg) { throw "install.ps1: $msg" }

  # The machine's value, not this process's: a 32-bit PowerShell reports x86.
  $osArch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
  if ($osArch -notin 'AMD64', 'ARM64') { Fail "$osArch is not supported; dazio runs on Windows amd64, and on arm64 under emulation" }

  if ($env:DAZIO_VERSION) {
    $version = $env:DAZIO_VERSION -replace '^v', ''
  } else {
    # The /releases/latest redirect names the tag, so no API call and no rate limit.
    try { $r = Invoke-WebRequest -UseBasicParsing -Method Head "$repo/releases/latest" }
    catch { Fail "could not reach GitHub to find the latest release: $_" }
    # Windows PowerShell and PowerShell 7 keep the final URL in different places.
    $latest = $r.BaseResponse.ResponseUri
    if (-not $latest) { $latest = $r.BaseResponse.RequestMessage.RequestUri }
    if ("$latest" -notmatch '/tag/v([^/]+)$') { Fail "could not read a version out of the latest-release redirect ($latest)" }
    $version = $Matches[1]
  }
  $tag = "v$version"
  $archive = "dazio_${version}_windows_amd64.zip"

  $existing = Get-Command dazio -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "dazio-install-$([guid]::NewGuid())"
  New-Item -ItemType Directory $tmp | Out-Null
  try {
    function Fetch($name) {
      try { Invoke-WebRequest -UseBasicParsing -OutFile (Join-Path $tmp $name) "$repo/releases/download/$tag/$name" }
      catch { Fail "could not download $name from release ${tag}: $_" }
    }
    Fetch $archive
    Fetch 'checksums.txt'

    # A cosign on PATH is taken at its word: a bad signature stops the install.
    # Without one, the checksum below is what everyone else gets.
    if (Get-Command cosign -ErrorAction SilentlyContinue) {
      Fetch 'checksums.txt.cosign.bundle'
      & cosign verify-blob (Join-Path $tmp 'checksums.txt') `
        --bundle (Join-Path $tmp 'checksums.txt.cosign.bundle') `
        --certificate-identity "$workflow@refs/tags/endpoint/$tag" `
        --certificate-oidc-issuer $oidcIssuer
      if ($LASTEXITCODE -ne 0) {
        Fail "checksums.txt for $tag is not signed by the release workflow (or this cosign is too old to read a v0.3 bundle); not installing"
      }
    }

    $want = @(foreach ($line in Get-Content (Join-Path $tmp 'checksums.txt')) {
        $sum, $name = $line -split '\s+', 2
        if ($name -eq $archive) { $sum }
      })
    $got = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp $archive)).Hash
    if ($want.Count -ne 1 -or $got -ne $want[0]) {
      Fail "$archive does not match its sha256 in checksums.txt; not installing"
    }

    Expand-Archive -Path (Join-Path $tmp $archive) -DestinationPath (Join-Path $tmp 'x')
    $exe = Join-Path $tmp 'x\dazio.exe'
    if (-not (Test-Path $exe)) { Fail "no dazio.exe in $archive" }

    $dir = $env:DAZIO_INSTALL_DIR
    if (-not $dir) { $dir = Join-Path $env:LOCALAPPDATA 'Programs\dazio' }
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dest = Join-Path $dir 'dazio.exe'
    # The daemon runs a staged copy under the state dir, never this file, so
    # nothing holds it open across an upgrade.
    Copy-Item -Force $exe $dest
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }

  # Read unexpanded and written back as the same registry type: REG_EXPAND_SZ
  # rewritten as REG_SZ stops entries like %USERPROFILE%\bin expanding.
  $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  try {
    $userPath = $reg.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    if (($userPath -split ';') -notcontains $dir) {
      $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
      if ($userPath) { $kind = $reg.GetValueKind('Path') }
      $reg.SetValue('Path', ((@($userPath -split ';' | Where-Object { $_ }) + $dir) -join ';'), $kind)
      # Clearing a variable that is not set broadcasts WM_SETTINGCHANGE, so
      # terminals opened from now on see the new PATH.
      [Environment]::SetEnvironmentVariable('DAZIO_INSTALL_PATH_UPDATED', $null, 'User')
    }
  } finally {
    $reg.Close()
  }
  if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }

  # Stops a running daemon, stages this binary and starts it again, so a rerun
  # is also the upgrade.
  & $dest service install
  if ($LASTEXITCODE -ne 0) { Fail "installed $dest, but service install failed" }

  if ($existing -and $existing.Source -ne $dest) {
    Write-Host ''
    Write-Host "Another dazio is on your PATH at $($existing.Source), and it is still the one"
    Write-Host "that runs. Remove it, or put $dir ahead of it."
  }

  Write-Host ''
  Write-Host "dazio $version installed to $dest"
  Write-Host 'Next: dazio scan'
}
