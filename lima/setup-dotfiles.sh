#!/usr/bin/env bash
# Runs inside the VM (via `sandbox <project> dotfiles`, and on the first start of
# a VM that has none yet). Installs chezmoi at a pinned, checksummed version and
# applies the dotfiles repo at DOTFILES_URL to the VM user's home.
# Env: DOTFILES_URL; MODE=ensure (apply only if no dotfiles are checked out yet)
#      or MODE=update (also pull and re-apply an existing checkout).
#
# The repo's own scripts run as the VM user, with sudo and the project's tokens
# in reach — the same trust as anything else installed in the VM. The clone is
# anonymous: no credential helper is consulted, so the project's token is never
# offered to the dotfiles host.
set -euo pipefail
: "${DOTFILES_URL:?}"
MODE="${MODE:-ensure}"

# To bump: https://github.com/twpayne/chezmoi/releases — chezmoi_<ver>_checksums.txt
CHEZMOI_VER="2.74.1"
CHEZMOI_SHA256_arm64="8c62619c4303770342e7c7e75d168b6cc6efee4ad5e4b994980de7cf794d68e2"
CHEZMOI_SHA256_amd64="ae01c66b1a6dbf563667c63fbbd9986b3cfa3c98dd266ddee732f63e8af2e9d1"

BIN="$HOME/.local/bin/chezmoi"
SRC="$HOME/.local/share/chezmoi"

if ! [ -x "$BIN" ] || [ "$("$BIN" --version 2>/dev/null | awk '{print $3}' | tr -d 'v,')" != "$CHEZMOI_VER" ]; then
    ARCH="$(dpkg --print-architecture)"
    case "$ARCH" in
        arm64) SHA256="$CHEZMOI_SHA256_arm64" ;;
        amd64) SHA256="$CHEZMOI_SHA256_amd64" ;;
        *) echo "no pinned chezmoi checksum for arch $ARCH" >&2; exit 1 ;;
    esac
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    curl --proto '=https' --tlsv1.2 -fsSL -o "$TMP/chezmoi.tar.gz" \
        "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VER}/chezmoi_${CHEZMOI_VER}_linux_${ARCH}.tar.gz"
    echo "$SHA256  $TMP/chezmoi.tar.gz" | sha256sum -c - >/dev/null
    tar -xzf "$TMP/chezmoi.tar.gz" -C "$TMP" chezmoi
    install -D -m 0755 "$TMP/chezmoi" "$BIN"
fi

export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=

if [ -d "$SRC/.git" ]; then
    CURRENT="$(git -C "$SRC" config --get remote.origin.url || true)"
    if [ "${CURRENT%.git}" != "${DOTFILES_URL%.git}" ]; then
        echo "$SRC is a checkout of '$CURRENT', not '$DOTFILES_URL'." >&2
        echo "Remove it inside the VM to switch repos." >&2
        exit 1
    fi
    [ "$MODE" = update ] || exit 0
    "$BIN" update </dev/null
else
    "$BIN" init --apply "$DOTFILES_URL" </dev/null
fi
