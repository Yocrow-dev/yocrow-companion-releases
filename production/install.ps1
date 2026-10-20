# Installs the Yocrow Companion (production) on Windows.
#   irm https://get.yocrow.dev/production/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 may default to older TLS, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ChannelUrl = if ($env:YOCROW_CHANNEL_URL) { $env:YOCROW_CHANNEL_URL } else { 'https://get.yocrow.dev/production' }
$DownloadUrl = if ($env:YOCROW_DOWNLOAD_URL) { $env:YOCROW_DOWNLOAD_URL } else { 'https://github.com/Yocrow-dev/yocrow-companion-releases/releases/download' }
$InstallDir = if ($env:YOCROW_INSTALL_DIR) { $env:YOCROW_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Yocrow\bin' }
$ArchivePrefix = 'yocrow'

# CIM reports the real CPU even inside x64-emulated PowerShell, where PROCESSOR_ARCHITECTURE lies.
if ($env:YOCROW_ARCH) {
    $arch = $env:YOCROW_ARCH.ToLower()
    if ($arch -ne 'amd64' -and $arch -ne 'arm64') { throw "Unsupported Windows architecture: $env:YOCROW_ARCH" }
} else {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
    $arch = switch ($cpu) {
        9 { 'amd64' }
        12 { 'arm64' }
        default {
            $name = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
            switch ($name) {
                'AMD64' { 'amd64' }
                'ARM64' { 'arm64' }
                default { throw "Unsupported Windows architecture: $name" }
            }
        }
    }
}

$tag = if ($env:YOCROW_VERSION) { $env:YOCROW_VERSION } else { (Invoke-RestMethod "$ChannelUrl/latest.txt").Trim() }
$tag = 'v' + $tag.TrimStart('v')
$archive = "${ArchivePrefix}_$($tag.TrimStart('v'))_windows_$arch.zip"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Host "Downloading Yocrow Companion $tag for windows/$arch"
    Invoke-WebRequest "$DownloadUrl/$tag/$archive" -OutFile (Join-Path $tmp $archive) -UseBasicParsing
    Invoke-WebRequest "$DownloadUrl/$tag/checksums.txt" -OutFile (Join-Path $tmp 'checksums.txt') -UseBasicParsing

    $line = Get-Content (Join-Path $tmp 'checksums.txt') | Where-Object { ($_ -split '\s+')[1] -eq $archive }
    if (-not $line) { throw "No checksum listed for $archive" }
    $expected = ($line -split '\s+')[0]
    $actual = (Get-FileHash (Join-Path $tmp $archive) -Algorithm SHA256).Hash
    if ($expected -ne $actual.ToLower()) { throw "Checksum mismatch for $archive" }

    $extracted = Join-Path $tmp 'extracted'
    Expand-Archive (Join-Path $tmp $archive) -DestinationPath $extracted -Force
    $binary = Join-Path $extracted 'yocrow.exe'
    if (-not (Test-Path $binary -PathType Leaf)) { throw 'Archive layout changed: yocrow.exe not found' }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item $binary (Join-Path $InstallDir 'yocrow.exe') -Force
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($env:YOCROW_NO_MODIFY_PATH -eq '1') {
    Write-Host "Skipped PATH setup. Add $InstallDir to your user PATH to run yocrow from any terminal."
} elseif (($userPath -split ';') -notcontains $InstallDir) {
    $newPath = if ($userPath) { "$InstallDir;$userPath" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added $InstallDir to your user PATH. Open a new terminal to use it everywhere."
}
if ($env:YOCROW_NO_MODIFY_PATH -ne '1' -and ($env:Path -split ';') -notcontains $InstallDir) {
    $env:Path = "$InstallDir;$env:Path"
}
Write-Host "Installed $(& (Join-Path $InstallDir 'yocrow.exe') --version) to $InstallDir"
Write-Host 'Next, run: yocrow login'
