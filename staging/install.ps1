# Installs the Yocrow Companion (staging) on Windows.
#   irm https://get.yocrow.dev/staging/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 may default to older TLS, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ChannelUrl = 'https://get.yocrow.dev/staging'
$DownloadUrl = 'https://github.com/Yocrow-dev/yocrow-companion-releases/releases/download'
# URL and key overrides are for local testing only.
$DevInstall = $env:YOCROW_INSTALL_DEV -eq '1'
if ($DevInstall -and $env:YOCROW_CHANNEL_URL) { $ChannelUrl = $env:YOCROW_CHANNEL_URL }
if ($DevInstall -and $env:YOCROW_DOWNLOAD_URL) { $DownloadUrl = $env:YOCROW_DOWNLOAD_URL }
$InstallDir = if ($env:YOCROW_INSTALL_DIR) { $env:YOCROW_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Yocrow\bin' }
$ArchivePrefix = 'yocrow-staging'
# Base64 SubjectPublicKeyInfo DER of the ECDSA P-256 key that signs checksums.txt.
$ChecksumsPublicKey = ''
if ($DevInstall -and $env:YOCROW_CHECKSUMS_PUBLIC_KEY) { $ChecksumsPublicKey = $env:YOCROW_CHECKSUMS_PUBLIC_KEY }
if (-not $ChecksumsPublicKey) { throw 'This installer has no checksums signing key' }

function Read-DerInteger([byte[]]$der, [ref]$pos) {
    if ($der[$pos.Value] -ne 0x02) { throw 'Checksums signature is invalid' }
    $len = [int]$der[$pos.Value + 1]
    if ($len -gt 33 -or $len -lt 1) { throw 'Checksums signature is invalid' }
    $start = $pos.Value + 2
    $pos.Value = $start + $len
    if ($pos.Value -gt $der.Length) { throw 'Checksums signature is invalid' }
    $value = [byte[]]$der[$start..($pos.Value - 1)]
    $skip = 0
    while ($skip -lt $value.Length - 1 -and $value[$skip] -eq 0) { $skip++ }
    $value = [byte[]]$value[$skip..($value.Length - 1)]
    if ($value.Length -gt 32) { throw 'Checksums signature is invalid' }
    $out = New-Object byte[] 32
    [Array]::Copy($value, 0, $out, 32 - $value.Length, $value.Length)
    return $out
}

# openssl writes DER, .NET verifies IEEE P1363 (r||s).
function Test-ChecksumsSignature([byte[]]$data, [byte[]]$der, [string]$keyBase64) {
    $spki = [Convert]::FromBase64String($keyBase64)
    $prefix = '3059301306072a8648ce3d020106082a8648ce3d030107034200'
    if ($spki.Length -ne 91 -or (($spki[0..25] | ForEach-Object { $_.ToString('x2') }) -join '') -ne $prefix -or $spki[26] -ne 0x04) {
        throw 'Embedded checksums signing key is not a P-256 public key'
    }
    if ($der.Length -lt 8 -or $der[0] -ne 0x30 -or $der[1] -ne $der.Length - 2) { throw 'Checksums signature is invalid' }
    $pos = 2
    $r = Read-DerInteger $der ([ref]$pos)
    $s = Read-DerInteger $der ([ref]$pos)
    if ($pos -ne $der.Length) { throw 'Checksums signature is invalid' }
    $point = New-Object Security.Cryptography.ECPoint
    $point.X = [byte[]]$spki[27..58]
    $point.Y = [byte[]]$spki[59..90]
    $p = New-Object Security.Cryptography.ECParameters
    $p.Curve = [Security.Cryptography.ECCurve+NamedCurves]::nistP256
    $p.Q = $point
    $ecdsa = [Security.Cryptography.ECDsa]::Create($p)
    try { return $ecdsa.VerifyData($data, [byte[]]($r + $s), [Security.Cryptography.HashAlgorithmName]::SHA256) } finally { $ecdsa.Dispose() }
}

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
$VersionPattern = '\A([0-9]+)\.([0-9]+)\.([0-9]+)(?:-staging\.([0-9]+))?\z'
if ($tag.Substring(1) -notmatch $VersionPattern) { throw 'Invalid version tag from the release channel' }
# A final release ranks above its staging builds.
function Get-VersionKey([string]$version) {
    if ($version -notmatch $VersionPattern) { return $null }
    $release = if ($Matches[4]) { 0 } else { 1 }
    $staging = if ($Matches[4]) { [long]$Matches[4] } else { 0 }
    return @([long]$Matches[1], [long]$Matches[2], [long]$Matches[3], $release, $staging)
}
$installedExe = Join-Path $InstallDir 'yocrow.exe'
if (-not $env:YOCROW_VERSION -and (Test-Path $installedExe -PathType Leaf)) {
    $installed = try { "$(& $installedExe version 2>$null | Select-Object -First 1)".Trim().TrimStart('v') } catch { '' }
    $old = Get-VersionKey $installed
    $new = Get-VersionKey $tag.Substring(1)
    if ($old) {
        for ($i = 0; $i -lt 5; $i++) {
            if ($new[$i] -gt $old[$i]) { break }
            if ($new[$i] -lt $old[$i]) { throw "Refusing to downgrade from $installed to $($tag.Substring(1)). Set YOCROW_VERSION to install an older version" }
        }
    }
}
$archive = "${ArchivePrefix}_$($tag.TrimStart('v'))_windows_$arch.zip"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Host "Downloading Yocrow Companion $tag for windows/$arch"
    Invoke-WebRequest "$DownloadUrl/$tag/$archive" -OutFile (Join-Path $tmp $archive) -UseBasicParsing
    Invoke-WebRequest "$DownloadUrl/$tag/checksums.txt" -OutFile (Join-Path $tmp 'checksums.txt') -UseBasicParsing

    Invoke-WebRequest "$DownloadUrl/$tag/checksums.txt.sig" -OutFile (Join-Path $tmp 'checksums.txt.sig') -UseBasicParsing
    $checksumBytes = [IO.File]::ReadAllBytes((Join-Path $tmp 'checksums.txt'))
    $signatureBytes = [IO.File]::ReadAllBytes((Join-Path $tmp 'checksums.txt.sig'))
    if (-not (Test-ChecksumsSignature $checksumBytes $signatureBytes $ChecksumsPublicKey)) { throw 'Checksums signature is invalid' }
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
