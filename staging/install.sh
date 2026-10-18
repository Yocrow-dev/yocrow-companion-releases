#!/bin/sh
# Installs the Yocrow Companion (staging) on macOS or Linux.
#   curl -fsSL https://get.yocrow.dev/staging/install.sh | sh
set -eu

CHANNEL_URL="${YOCROW_CHANNEL_URL:-https://get.yocrow.dev/staging}"
DOWNLOAD_URL="${YOCROW_DOWNLOAD_URL:-https://github.com/Yocrow-dev/yocrow-companion-releases/releases/download}"
ARCHIVE_PREFIX="yocrow-staging"
INSTALL_DIR="${YOCROW_INSTALL_DIR:-$HOME/.local/bin}"

fail() { echo "yocrow install: $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported OS $(uname -s). Use install.ps1 on Windows." ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "unsupported architecture $(uname -m)" ;;
esac

command -v curl >/dev/null 2>&1 || fail "curl is required"
if command -v sha256sum >/dev/null 2>&1; then sha="sha256sum"
elif command -v shasum >/dev/null 2>&1; then sha="shasum -a 256"
else fail "sha256sum or shasum is required"; fi

tag="${YOCROW_VERSION:-$(curl -fsSL "$CHANNEL_URL/latest")}" || fail "could not resolve the latest version"
tag="v${tag#v}"
archive="${ARCHIVE_PREFIX}_${tag#v}_${os}_${arch}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Yocrow Companion $tag for $os/$arch"
curl -fsSL -o "$tmp/$archive" "$DOWNLOAD_URL/$tag/$archive" || fail "download failed for $archive"
curl -fsSL -o "$tmp/checksums.txt" "$DOWNLOAD_URL/$tag/checksums.txt" || fail "checksum download failed"

expected="$(awk -v f="$archive" '$2 == f { print $1 }' "$tmp/checksums.txt")"
[ -n "$expected" ] || fail "no checksum listed for $archive"
actual="$(cd "$tmp" && $sha "$archive" | awk '{ print $1 }')"
[ "$expected" = "$actual" ] || fail "checksum mismatch for $archive"

tar -xzf "$tmp/$archive" -C "$tmp" yocrow || fail "archive does not contain yocrow"
mkdir -p "$INSTALL_DIR"
install -m 0755 "$tmp/yocrow" "$INSTALL_DIR/yocrow"

echo "Installed $("$INSTALL_DIR/yocrow" --version 2>/dev/null || echo yocrow) to $INSTALL_DIR/yocrow"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Add $INSTALL_DIR to your PATH, for example: export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac
echo "Next, run: yocrow login"
