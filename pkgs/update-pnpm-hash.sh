#!/usr/bin/env bash
# Recompute pnpmDeps.hash in pkgs/deemix.nix from the current pnpm-lock.yaml.
#
# The hash is a fixed-output hash over the vendored pnpm store, so it goes stale
# every time the lockfile changes and the nix build then fails offline with
# ERR_PNPM_NO_OFFLINE_TARBALL. Run this after any dependency change; CI runs it
# automatically on pull requests (.github/workflows/update-nix-pnpm-hash.yml).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
nix_file=pkgs/deemix.nix

matches=$(grep -c 'hash = "' "$nix_file")
if [ "$matches" -ne 1 ]; then
	echo "expected exactly one 'hash = \"...\"' in $nix_file, found $matches" >&2
	exit 1
fi

old=$(sed -n 's/.*hash = "\(.*\)";.*/\1/p' "$nix_file")

# An empty hash makes the fixed-output derivation fail with the real hash in the
# error, which is the only way to learn it.
sed -i 's|hash = ".*";|hash = "";|' "$nix_file"
log=$(nix build .#default.pnpmDeps --no-link 2>&1 || true)
new=$(printf '%s\n' "$log" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | tail -1)

if [ -z "$new" ]; then
	sed -i "s|hash = \"\";|hash = \"$old\";|" "$nix_file"
	echo "could not determine the new hash; nix said:" >&2
	printf '%s\n' "$log" >&2
	exit 1
fi

sed -i "s|hash = \"\";|hash = \"$new\";|" "$nix_file"

if [ "$old" = "$new" ]; then
	echo "pnpmDeps.hash is already up to date ($new)"
else
	echo "pnpmDeps.hash updated: $old -> $new"
fi
