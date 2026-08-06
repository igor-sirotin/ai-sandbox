#!/usr/bin/env bash
# Runs inside the VM (via `sandbox <project> keys`). Generates a GPG commit-
# signing key for the primary identity and configures git to sign every commit
# and tag with it.
# Env: GNAME, EMAIL.  Prints the GPG key id on stdout (notices go to stderr).
#
# The key is passphraseless — commits have to sign unattended — and it lives in a
# VM whose agent runs with --dangerously-skip-permissions, so treat it as
# exfiltratable. It therefore *expires*: a stolen key stops being able to produce
# Verified commits in your name once the year is out. Re-running `sandbox
# <project> keys` renews an existing key rather than piling up new ones.
set -e
: "${GNAME:?}"; : "${EMAIL:?}"

KEY_EXPIRY="1y"
RENEW_WINDOW=$(( 30 * 24 * 3600 ))   # renew when less than 30 days remain

export GNUPGHOME="$HOME/.gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

gpg_batch() { gpg --batch --yes --pinentry-mode loopback --passphrase '' "$@"; }

if ! gpg --list-secret-keys "$EMAIL" >/dev/null 2>&1; then
    gpg_batch --quick-generate-key "$GNAME <$EMAIL>" ed25519 sign "$KEY_EXPIRY" >/dev/null 2>&1
fi

FPR="$(gpg --list-secret-keys --with-colons "$EMAIL" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
KEYID="$(gpg --list-secret-keys --with-colons --keyid-format=long "$EMAIL" 2>/dev/null | awk -F: '/^sec:/{print $5; exit}')"
[ -n "$FPR" ] && [ -n "$KEYID" ] || { echo "gpg key generation failed" >&2; exit 1; }

# Renew if the key never expires (created by an older sandbox) or is close to it.
EXPIRES="$(gpg --list-keys --with-colons "$FPR" 2>/dev/null | awk -F: '/^pub:/{print $7; exit}')"
if [ -z "$EXPIRES" ] || [ "$EXPIRES" -lt "$(( $(date +%s) + RENEW_WINDOW ))" ]; then
    if gpg_batch --quick-set-expire "$FPR" "$KEY_EXPIRY" >/dev/null 2>&1; then
        EXPIRES="$(gpg --list-keys --with-colons "$FPR" 2>/dev/null | awk -F: '/^pub:/{print $7; exit}')"
        echo "   signing key expiry set to +$KEY_EXPIRY" >&2
    else
        echo "   !! could not set an expiry on the signing key" >&2
    fi
fi
if [ -n "$EXPIRES" ]; then
    echo "   signing key expires: $(date -u -d "@$EXPIRES" +%Y-%m-%d 2>/dev/null || echo "$EXPIRES")" >&2
else
    echo "   !! signing key does not expire" >&2
fi

git config --global gpg.format openpgp
git config --global user.signingkey "$KEYID"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global user.name  "$GNAME"
git config --global user.email "$EMAIL"

echo "$KEYID"
