#!/usr/bin/env bash
# git credential helper for the Claude sandbox.
# Serves per-scope GitHub tokens keyed by "<host>/<org>" prefix, read from
# ~/.config/sandbox/credentials (TAB-separated "<host>/<org>\t<token>", mode 600).
# Only answers `get`; returns nothing (exit 0) on no match so git falls through
# to the next helper (e.g. gh's). Enable with credential.useHttpPath=true so the
# repo path is available for routing.
#
# Tokens are only ever handed to an https:// request: a remote configured with
# http:// — or one reached through a protocol downgrade — would put the PAT on
# the wire in cleartext, so those requests get no answer.
set -u
[ "${1:-}" = get ] || exit 0

cred_file="$HOME/.config/sandbox/credentials"
[ -r "$cred_file" ] || exit 0

protocol=""; host=""; path=""
while IFS='=' read -r k v; do
    case "$k" in
        protocol) protocol="$v" ;;
        host)     host="$v" ;;
        path)     path="$v" ;;
        "")       break ;;   # blank line terminates the request
    esac
done
[ "$protocol" = https ] || exit 0
[ -n "$host" ] || exit 0
url="$host"; [ -n "$path" ] && url="$host/$path"

# Pick the longest "<host>/<org>[/...]" scope that prefixes the request URL.
best_scope=""; best_token=""
while IFS=$'\t' read -r scope token; do
    [ -n "$scope" ] || continue
    case "$url/" in
        "$scope/"*)
            if [ "${#scope}" -gt "${#best_scope}" ]; then
                best_scope="$scope"; best_token="$token"
            fi ;;
    esac
done < "$cred_file"

[ -n "$best_token" ] || exit 0
printf 'username=x-access-token\n'
printf 'password=%s\n' "$best_token"
