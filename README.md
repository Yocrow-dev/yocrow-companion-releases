# Yocrow Companion releases

Release binaries and installers for the Yocrow Companion. Source lives in a private repository.

## Install

macOS and Linux

```sh
curl -fsSL https://get.yocrow.dev/production/install.sh | sh
```

Windows PowerShell

```powershell
irm https://get.yocrow.dev/production/install.ps1 | iex
```

Then run `yocrow login`.

## Staging

Staging builds are for testing new changes before they ship. They are unstable and not meant for regular use.

macOS and Linux

```sh
curl -fsSL https://get.yocrow.dev/staging/install.sh | sh
```

Windows PowerShell

```powershell
irm https://get.yocrow.dev/staging/install.ps1 | iex
```

## Options

| Variable | Purpose |
| --- | --- |
| `YOCROW_VERSION` | Install a specific tag such as `v1.0.0`. |
| `YOCROW_INSTALL_DIR` | Install location. Defaults to `~/.local/bin` or `%LOCALAPPDATA%\Yocrow\bin`. |
| `YOCROW_NO_MODIFY_PATH` | Set to `1` to skip adding the install location to PATH. By default the installer updates your shell profile or Windows user PATH. |
| `YOCROW_ARCH` | Windows only. Force `amd64` or `arm64` instead of detecting the CPU. |

Every download is checked against the release `checksums.txt` before it is installed.
