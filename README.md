# Local agent sandbox (prototype)

Run Claude Code, OpenAI Codex, or Gemini CLI inside a disposable rootless Podman
container, without mounting the host home directory. Targets Linux and Podman
Machine on macOS. **Not yet tested end-to-end with live Podman images.**

## Overview

```text
                     host (Linux / macOS)
  +-------------------------------------------------------+
  | agent launcher                                        |
  |  - choose agent + image                               |
  |  - validate Git roots + scan names for secret risks   |
  |  - pass selected project bind mounts                  |
  |                                                       |
  |  project A ---- RW ----> /workspace                    |
  |     .git/  -- RO/RW --> /workspace/.git                |
  |  project B ---- RW ----> /projects/2-project-b         |
  |     .git/  -- RO/RW --> /projects/2-project-b/.git    |
  |                                                       |
  |  Podman volume agent-home-claude ------------------+   |
  |  Podman volume agent-maven-cache ------------------+   |
  +---------------------------------------------------|---+
                                                      |
                     disposable container            |
  +---------------------------------------------------|---+
  | agent-base (Claude / Codex / Gemini, Git, rg, jq)  |   |
  |       + agent-backend (Java 17, Maven)             |   |
  |                                                   v   |
  |                 /home/agent (persistent per agent)     |
  |                 /home/agent/.m2/repository (shared)    |
  |            /workspace + /projects (bind mounts)       |
  +-------------------------------------------------------+
```

## Build and install

Prerequisites: Podman (with an initialized and running Podman machine on macOS),
[Bash](https://www.gnu.org/software/bash/), and optionally
[Task](https://taskfile.dev/) for convenient image builds.

```sh
task build                # builds base, then backend
task install              # installs launcher at ~/.local/bin/agent
```

Without Task:

```sh
podman build -f Containerfile.base -t localhost/agent-base:latest .
podman build -f Containerfile.backend -t localhost/agent-backend:latest .
bash ./install.sh
```

The installer only copies the `agent` launcher. Override its destination with
`INSTALL_DIR="$HOME/bin" bash ./install.sh`. Make sure it is on `PATH`.
Images are updated explicitly by rebuilding; neither the launcher nor the
container automatically updates agent versions.

## Usage

From the root of a repository:

```sh
agent claude
agent codex
agent gemini --image base
agent claude --git rw      # permit staging, commits and branches
agent bash --image backend
```

Mount multiple projects (first = `/workspace`; subsequent mounts are named under
`/projects/`):

```sh
agent claude --project "$HOME/code/backend" --project "$HOME/code/shared-library"
agent codex --project . --project ../common -- --help
```

## Maven cache and VPN connectivity

When using `--image backend` (the default), the launcher mounts a named
`agent-maven-cache` volume at `/home/agent/.m2/repository`. This is **shared
between all agent CLIs and projects**, survives container removal, and is
separate from the host's `~/.m2` directory. The `base` image does not mount it.

The cache does **not** include Maven `settings.xml`. Private Maven repositories
may still require separate mirror configuration and credentials; do not mount
your host settings file without reviewing it. A shared writable dependency
cache is not a trust boundary: any agent can modify cached artifacts.

Test whether the default network path reaches a service available on the VPN:

```sh
bash ./vpn-test.sh
# or
 task vpn-test
# optional alternative endpoint
bash ./vpn-test.sh 'http://mq.gbif.org:15672/'
```

The diagnostic compares host and container HTTP connectivity (including DNS)
using `curl`. Any HTTP status, including 401 or 403, confirms that a server
responded; the script does not send credentials. It needs the base image built
first (`task base`). On macOS, Podman networking passes through its Linux VM;
some university VPNs may prevent private DNS or routes from working there.


With no `--project` flags, the current directory is the primary project.
`--` separates launcher flags from the agent's own flags.

Before starting Podman, the launcher checks each selected project for likely
credential filenames (`.env`, `.env.local`, `.npmrc`, `.netrc`, private keys,
service account JSON, etc.), common hidden credential directories, and mounts
that encompass the host home directory. It scans filenames only, at most five
directory levels deep, and skips common test/fixture/example directories and
generated dependencies. Up to eight matching files per project are reported.
The warnings are consolidated into **one confirmation** (or accepted by
`--yes`); nothing is blocked permanently. Treat this as a sanity check, not
secret detection: arbitrary filenames, deeper directories and contents are not
examined. The checks apply to **every** mounted project.

For every project, the launcher checks whether a regular `.git/` directory is
present at its root. By default (`--git ro`), it is overmounted read-only.
Use `--git rw` to allow writes to Git metadata for all mounted projects; this
skips the nested read-only mount. The flag does not change source-file access,
which remains read/write in both modes. Git write access does not bypass
secret-file warnings or confirmation. Otherwise the
launcher warns and asks for confirmation before continuing; use `--yes` for
noninteractive execution (including bypassing secret warnings). This includes Git worktrees (`.git` file), which
are not supported for Git metadata protection yet. Their Git metadata may
reside outside the mounted directory, even with `--git rw`. Passing a subdirectory
rather than the repo root triggers the same warning.

## Lifetime, persistence and concurrent projects

- `podman run --rm -it`: a fresh container is created for each invocation and
  deleted on exit. There is no automatic restart or resumption of the process.
- Home/config volumes are **persistent per agent CLI**, named `agent-home-claude`,
  `agent-home-codex`, `agent-home-gemini` (and `agent-home-bash` for shells).
  Credentials, settings and session files stored under `/home/agent` survive.
- Volumes are **shared across all projects for that agent**, not per project.
  This is intentional for convenient sign-in, but means agent-side history and
  config can be accessed by subsequent sessions using the same agent.
- The Maven repository volume is shared among backend agent sessions, including
  concurrent sessions; cache writes can conflict and downloaded artifacts should
  not be treated as trusted merely because they are cached.
- Concurrent agent sessions may share the same home volume and project files.
  Do not run simultaneous writers on the same worktree without coordination.
- All source edits are immediately reflected on the host via bind mounts.
  Removing a container does **not** undo source modifications.
- See persisted volumes with `podman volume ls`. Removing a home volume loses
  the agent's stored authentication and settings.

## Security model and limitations

- Project directories are writable; nested ordinary `.git/` directories are
  read-only, as confirmed in a simple bind-mount test on macOS Podman.
- No host `$HOME`, host SSH agent, browser profile or Podman/Docker socket is
  deliberately exposed; the agent has its own persistent configuration volume.
- Rootless Podman is the intended setup; dropped Linux capabilities, no-new-privileges,
  and resource limits are enabled. On macOS Podman operates inside a Linux VM.
- **Network access is unrestricted**; agents can transmit any files visible
  through mounts, including `.env` files and secrets inside repositories.
- Read-only `.git` mounts are a practical guard against ordinary Git metadata
  writes, **not** a verified protection against all hostile filesystem tricks.
- Mounted project paths can contain credentials, symlinks or nested repositories.
  Inspect them before granting access. Mounting multiple repositories increases
  how much data the agent can read or alter.
- `HOME` is persistent, and each agent can inspect its own credentials and
  history. Do not share these volumes with untrusted containers.
- Login flows may require copying a browser URL or device code from the CLI.
- The Node.js base and npm-installed agent CLIs use floating versions. Pin
  versions and establish a patch/update policy before team rollout.
- Not yet covered: Git worktree metadata, automated network allowlists,
  project-secret exclusion, read-only container rootfs, SELinux labeling,
  Maven settings/credentials and automated Podman integration tests.
