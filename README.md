<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" width="360" alt="Dazio by Boost Security">
  </picture>
</p>

Dazio catches malicious dependencies at install, finds exposed secrets before
malware does, and hardens your dev toolchain.

Free.

**📖 Documentation: [boostsecurityio.github.io/dazio](https://boostsecurityio.github.io/dazio/)**

## Install

Homebrew, on macOS or Linux:

```sh
brew install boostsecurityio/tap/dazio
```

Without Homebrew, on macOS or Linux:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/boostsecurityio/dazio/HEAD/install.sh)"
```

[Install](https://boostsecurityio.github.io/dazio/docs/install/) covers
upgrades, mise and the script's options. Then run your first scan:

```sh
dazio scan
```

## Learn more

- [Quick start](https://boostsecurityio.github.io/dazio/docs/quick-start/):
  the first scan and continuous protection
- [What it checks](https://boostsecurityio.github.io/dazio/docs/what-it-checks/):
  [malware](https://boostsecurityio.github.io/dazio/docs/what-it-checks/#malware-at-install),
  [secrets](https://boostsecurityio.github.io/dazio/docs/what-it-checks/#exposed-secrets),
  [toolchain hardening](https://boostsecurityio.github.io/dazio/docs/what-it-checks/#toolchain-hardening)
  and [coverage by ecosystem](https://boostsecurityio.github.io/dazio/docs/what-it-checks/#coverage-by-ecosystem)
- [CLI and configuration reference](https://boostsecurityio.github.io/dazio/docs/reference/)
- [How it works & privacy](https://boostsecurityio.github.io/dazio/docs/privacy/)
- [Uninstall](https://boostsecurityio.github.io/dazio/docs/uninstall/)
- [FAQ](https://boostsecurityio.github.io/dazio/docs/faq/)

## Support

Bugs and questions go to this repository's
[Issues](https://github.com/boostsecurityio/dazio/issues). The source is
closed; this repository hosts the releases.

> **Looking for more?** Boost's
> [Developer Endpoint Protection](https://boostsecurity.io/solution/developer-endpoint)
> adds central management, reporting and support on top of everything Dazio
> does.
