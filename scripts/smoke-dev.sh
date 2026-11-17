#!/usr/bin/env bash
set -euo pipefail

# Run inside agent-dev through its entrypoint, including as a non-root user.
for tool in ruby bundle node npm npx pnpm yarn python python3 uv uvx java javac java25 javac25 mvn \
  go rustup rustc cargo rustfmt cargo-clippy cc c++ make cmake pkg-config \
  git git-lfs rg fd jq eza yq task helm kubeconform yamllint shellcheck shfmt \
  sqlite3 psql pg_dump pg_restore tar gzip xz bzip2 zstd zip unzip diff patch \
  file xxd rsync lsof fuser ip dig nc time timeout playwright; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
node --version
python --version
ruby --version
java -version
java -version 2>&1 | rg 'version "17\.'
javac -version 2>&1 | rg '^javac 17\.'
java25 -version 2>&1 | rg 'version "25[."]'
javac25 -version 2>&1 | rg '^javac 25([.]|$)'
env JAVA_HOME="$JAVA25_HOME" PATH="$JAVA25_HOME/bin:$PATH" mvn -version | rg 'Java version: 25([,.]|$)'
go version
rustc --version
cargo fmt --version
cargo clippy --version
task --version
helm version --short
kubeconform -v
bash -c 'type nvm >/dev/null; nvm exec default node --version'
python -c 'import ssl, sqlite3; print("Python SSL and SQLite available")'
node -e 'const {chromium} = require("/usr/local/lib/node_modules/playwright"); (async () => { const browser = await chromium.launch({headless:true}); const page = await browser.newPage(); await page.setContent("<title>smoke</title>"); if (await page.title() !== "smoke") throw Error("Unexpected title"); await browser.close(); })().catch(e => { console.error(e); process.exit(1); });'
echo 'Development image smoke checks passed.'
