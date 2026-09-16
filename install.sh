#!/usr/bin/env bash
# Installs or upgrades dazio into ~/.local/bin, for people without Homebrew.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/boostsecurityio/dazio/HEAD/install.sh)"
#
# Piped into `bash -c`, so nothing here may read $0 or the working directory.
# macOS ships bash 3.2: no associative arrays, no ${var,,}.
#
set -euo pipefail

repo=https://github.com/boostsecurityio/dazio
# The archives are built in the private monorepo and published here, so the
# keyless signing identity names that repository's release workflow at the tag
# it ran on — matched exactly, because any workflow on any branch satisfying it
# is a signature anyone with push access could produce.
workflow=https://github.com/boostsecurityio/boostfree-endpoint/.github/workflows/release-endpoint.yml
oidc_issuer=https://token.actions.githubusercontent.com

die() { echo "install.sh: $*" >&2; exit 1; }

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) die "$(uname -s) is not supported; dazio ships for Linux and macOS on amd64 and arm64" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "$(uname -m) is not supported; dazio ships for Linux and macOS on amd64 and arm64" ;;
esac

# Follow the symlink chain by hand: `readlink -f` is GNU, and BSD readlink only
# grew it in macOS 12.3. The hop limit is there for a symlink that loops.
resolve() {
  local path=$1 target hops=0
  while [ -L "$path" ] && [ "$hops" -lt 16 ]; do
    target=$(readlink "$path")
    case "$target" in
      /*) path=$target ;;
      *) path=$(dirname "$path")/$target ;;
    esac
    hops=$((hops + 1))
  done
  printf '%s\n' "$path"
}

# A cask-installed dazio is a symlink into the Caskroom, and replacing it here
# would leave brew owning a path it no longer wrote. `brew upgrade` is the
# upgrade for that machine.
existing=$(command -v dazio || true)
if [ -n "$existing" ]; then
  case "$(resolve "$existing")" in
    */Caskroom/*)
      echo "dazio is installed with Homebrew ($existing). Upgrade it with:"
      echo
      echo "  brew upgrade dazio"
      exit 0
      ;;
  esac
fi

# Homebrew is the recommended install, so someone who has brew and lands here
# anyway is asked once, on a first install only. Enter is yes (ADR-0008), and a
# read that finds no terminal answers the same way.
if [ -z "$existing" ] && command -v brew > /dev/null 2>&1; then
  echo "You have Homebrew, and the recommended install is:"
  echo
  echo "  brew install boostsecurityio/tap/dazio"
  echo
  printf 'Install with this script instead? [Y/n] '
  read -r reply < /dev/tty 2> /dev/null || reply=
  case "$reply" in
    [Nn]*) echo "Nothing installed."; exit 0 ;;
  esac
  echo
fi

# The /releases/latest redirect names the tag, so no API call, no token, no jq.
if [ -n "${DAZIO_VERSION:-}" ]; then
  version=${DAZIO_VERSION#v}
else
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$repo/releases/latest") \
    || die "could not reach GitHub to find the latest release"
  version=${latest##*/tag/v}
  [ "$version" != "$latest" ] \
    || die "could not read a version out of the latest-release redirect ($latest)"
fi
tag=v$version

if command -v sha256sum > /dev/null 2>&1; then
  sha=(sha256sum)
elif command -v shasum > /dev/null 2>&1; then
  sha=(shasum -a 256)
else
  die "neither sha256sum nor shasum is on PATH; cannot verify the download"
fi

staged=
tmp=$(mktemp -d)
cleanup() {
  rm -rf "$tmp"
  if [ -n "$staged" ]; then rm -f "$staged"; fi
}
trap cleanup EXIT

archive=dazio_${version}_${os}_${arch}.tar.gz
curl -fsSL -o "$tmp/$archive" "$repo/releases/download/$tag/$archive" \
  || die "no $archive in release $tag"
curl -fsSL -o "$tmp/checksums.txt" "$repo/releases/download/$tag/checksums.txt" \
  || die "no checksums.txt in release $tag"

# A cosign on PATH is taken at its word: a bad signature stops the install. No
# cosign, no signature check and nothing said about it — the checksum below is
# what everyone else gets, and a warning nobody can act on is just noise.
if command -v cosign > /dev/null 2>&1; then
  curl -fsSL -o "$tmp/checksums.txt.cosign.bundle" \
    "$repo/releases/download/$tag/checksums.txt.cosign.bundle" \
    || die "no checksums.txt.cosign.bundle in release $tag"
  cosign verify-blob "$tmp/checksums.txt" \
    --bundle "$tmp/checksums.txt.cosign.bundle" \
    --certificate-identity "$workflow@refs/tags/endpoint/$tag" \
    --certificate-oidc-issuer "$oidc_issuer" \
    || die "checksums.txt for $tag is not signed by the release workflow (or this cosign is too old to read a v0.3 bundle); not installing"
fi

# -c reads the filename out of the line, so it runs where the archive is.
(cd "$tmp" && grep " $archive\$" checksums.txt | "${sha[@]}" -c -) > /dev/null \
  || die "$archive does not match its sha256 in checksums.txt; not installing"

tar -xzf "$tmp/$archive" -C "$tmp" dazio || die "no dazio binary in $archive"

dir=${DAZIO_INSTALL_DIR:-$HOME/.local/bin}
mkdir -p "$dir" || die "could not create $dir"
dest=$dir/dazio
# Whether this run replaces a binary, which is not the same question as whether
# some dazio is on PATH: a registration records the path it was installed from,
# so bouncing the daemon only moves it onto what this script wrote when what it
# wrote is what the daemon was already running.
upgrade=false
if [ -e "$dest" ]; then
  upgrade=true
fi

# Staged inside $dir so the move is a rename on one filesystem: the replacement
# is atomic, and a running daemon keeps its unlinked inode instead of being
# written out from under itself.
staged=$dest.install.$$
cp "$tmp/dazio" "$staged" || die "could not write to $dir"
chmod 755 "$staged"
mv -f "$staged" "$dest"
staged=

# The daemon an upgrade left running still serves the replaced binary, and only
# its supervisor can move it onto the new one (ADR-0011). The verb exits 0 and
# says so where nothing is registered, so it is safe unconditionally here — but
# a first install has nothing to bounce and nothing to say about it.
if [ "$upgrade" = true ]; then
  "$dest" service restart || die "installed $dest, but the daemon did not restart"
fi

if [ -n "$existing" ] && [ "$(resolve "$existing")" != "$dest" ]; then
  echo
  echo "Another dazio is on your PATH at $existing, and it is still the one that"
  echo "runs. Remove it, or put $dir ahead of it."
fi

case ":$PATH:" in
  *":$dir:"*) ;;
  *)
    echo
    echo "$dir is not on your PATH. Add it:"
    echo
    echo "  export PATH=\"$dir:\$PATH\""
    ;;
esac

echo
echo "dazio $version installed to $dest"
echo "Next: dazio scan"
