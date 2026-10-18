# Yocrow Companion releases

Release binaries and installers for the Yocrow Companion. Source lives in a private repository.

## Staging

macOS and Linux

```sh
curl -fsSL https://get.yocrow.dev/staging/install.sh | sh
```

Windows PowerShell

```powershell
irm https://get.yocrow.dev/staging/install.ps1 | iex
```

Then run `yocrow login`.

## Production

Available after the first production release.

macOS and Linux

```sh
curl -fsSL https://get.yocrow.dev/production/install.sh | sh
```

Windows PowerShell

```powershell
irm https://get.yocrow.dev/production/install.ps1 | iex
```

## Options

| Variable | Purpose |
| --- | --- |
| `YOCROW_VERSION` | Install a specific tag such as `v0.1.0-staging.1`. |
| `YOCROW_INSTALL_DIR` | Install location. Defaults to `~/.local/bin` or `%LOCALAPPDATA%\Yocrow\bin`. |
| `YOCROW_ARCH` | Windows only. Force `amd64` or `arm64` instead of detecting the CPU. |

Every download is checked against the release `checksums.txt` before it is installed.
