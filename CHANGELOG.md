# Changelog

Changes to the agent launcher, container images, and build tasks are grouped
by date, newest first.

## 2026-11-20

- `task build` refreshes Debian's CA bundle and installs current versions of Claude Code, Codex, and Gemini CLI on every run. The refresh runs after the shared dev toolchains and Chromium so their layers can be reused.
- Added `task full-rebuild` to rebuild the foundation, base, and dev images without cached layers, and `task cleanup` to prune dangling images on the current Podman connection.
- Added `agent --memory` to set a session's memory limit. The default is 6 GiB.
- Added `task backup` and `task restore` for agent home volumes and the shared Maven cache.

## 2026-11-19

- Fixed the Podman mount option that adjusts ownership of the agent home volume.

## 2026-11-17

- Made the shared development image the launcher default and kept `backend` as a compatibility alias.
- Added development toolchains for Node.js, Python, Ruby, Java, Go, Rust, and C/C++, plus browser and Kubernetes manifest tooling.
- Fixed tool discovery through `PATH`. Added Java 25 alongside the default Java 17.

## 2026-11-16

- Added preflight checks for common credential filenames and mounts that include the host home directory.
- Added a shared Maven cache and a diagnostic for testing VPN connectivity from the container.
- Made Git metadata read-only by default, with `--git rw` for workflows that need to write it.
- Mounted each project under its own directory in `/workspace`, with the first project as the working directory.
