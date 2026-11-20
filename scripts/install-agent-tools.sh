#!/bin/sh
set -eu

apt-get update
apt-get install -y --no-install-recommends ca-certificates
update-ca-certificates
rm -rf /var/lib/apt/lists/*

# Follow upstream releases for all three agent CLIs.
npm_cache=$(mktemp -d)
trap 'rm -rf "$npm_cache"' EXIT
npm install --global --cache "$npm_cache" --no-audit --no-fund \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli
