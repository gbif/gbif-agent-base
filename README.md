# Local agent sandbox (prototype)

Run Claude Code, OpenAI Codex, or Gemini CLI inside a disposable rootless Podman
container, without mounting the host home directory. Targets Linux and Podman
Machine on macOS.

## Overview

```text
                     host (Linux / macOS)
  +-------------------------------------------------------+
  | agent launcher                                        |
  |  - choose agent + image                               |
  |  - validate Git roots + scan names for secret risks   |
  |  - pass selected project bind mounts                  |
  |                                                       |
  |  project A ---- RW ----> /workspace/project-a          |
  |     .git/  -- RO/RW --> /workspace/project-a/.git      |
  |  project B ---- RW ----> /workspace/project-b          |
  |     .git/  -- RO/RW --> /workspace/project-b/.git      |
  |                                                       |
  |  Podman volume agent-home-claude ------------------+   |
  |  Podman volume agent-maven-cache ------------------+   |
  +---------------------------------------------------|---+
                                                      |
                     disposable container            |
  +---------------------------------------------------|---+
  | agent-base (Claude / Codex / Gemini, Git, rg, jq)  |   |
  |       + agent-dev (shared development tools)      |   |
  |                                                   v   |
  |                 /home/agent (persistent per agent)     |
  |                 /home/agent/.m2/repository (shared)    |
  |             /workspace/<project-name>/ (mounts)       |
  +-------------------------------------------------------+
```

## Build and install

Prerequisites: Podman (with an initialized and running Podman machine on macOS),
[Bash](https://www.gnu.org/software/bash/), and optionally
[Task](https://taskfile.dev/) for convenient image builds.

```sh
task build                # builds base, then dev
task install              # installs launcher at ~/.local/bin/agent
```

Without Task:

```sh
podman build -f Containerfile.base -t localhost/agent-base:latest .
podman build -f Containerfile.dev -t localhost/agent-dev:latest .
bash ./install.sh
```

The installer only copies the `agent` launcher. Override its destination with
`INSTALL_DIR="$HOME/bin" bash ./install.sh`. Make sure it is on `PATH`.
Images are updated explicitly by rebuilding; neither the launcher nor the
container automatically updates agent versions.

## Shared development image

`agent-base` contains the agent CLIs and common shell tools. `agent-dev` adds:

- Ruby and Bundler; Node/npm with nvm, pnpm and Yarn.
- Python 3.13 with uv for additional Python versions and environments, plus system Python.
- Java 17 (default) and Java 25 JDKs with Maven, Go, and Rust through rustup with Cargo, rustfmt and Clippy.
- GCC/G++, make, CMake, pkg-config and common native extension headers.
- SQLite and PostgreSQL clients, without database servers.
- eza, yq, go-task (`task`), ShellCheck, shfmt, yamllint and Git LFS.
- Archive, file inspection, process and network diagnostic utilities, UTF-8 locales and timezone data.
- Playwright with Chromium and its system dependencies for browser checks.
- Helm and kubeconform for local chart rendering and manifest validation.

GitHub CLI (`gh`) and kubectl are intentionally excluded. No cluster credentials,
container socket or host kubeconfig are mounted automatically. Kubernetes schemas
are not bundled: kubeconform downloads schemas when validating, and custom resource
schemas must be supplied separately. For example:

```sh
helm lint ./chart
helm template example ./chart | kubeconform -strict -summary
```

The launcher defaults to `dev`; `--image backend` remains an alias for `dev`.
`task backend` also builds the legacy image tag for direct Podman callers.
Run `task smoke` after building to check tools and a headless browser as an
unprivileged user with a fresh temporary home.

Baked toolchains live outside `/home/agent`, so existing home volumes do not hide
new image installations. nvm is loaded for interactive and noninteractive Bash;
other compatible shells can source `/opt/nvm/nvm.sh` after setting
`NVM_DIR=$HOME/.nvm`. User-installed Node/Python/Rust versions and Ruby gems
persist in the home volume. Rust's initial `image` toolchain links to the bundled
toolchain; install a named version with rustup when a project needs one.
Ruby uses Debian's version; multiple Ruby versions need a separate version manager.
Use project Maven/Gradle wrappers and project-pinned dependencies where available.

Plain `java` and `javac` use Java 17. `java25` and `javac25` run the bundled
Eclipse Temurin 25 JDK directly. Agents can select Java 25 for a single build:

```sh
JAVA_HOME="$JAVA25_HOME" PATH="$JAVA25_HOME/bin:$PATH" mvn verify
# Or use the same environment with ./mvnw or ./gradlew.
```

To select it for the rest of a shell session:

```sh
export JAVA_HOME="$JAVA25_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

`JAVA25_HOME` points to `/opt/java25`, outside the persistent home volume.
Runtime selection applies to that process and its children; new containers
start with Java 17 again. Rebuild `agent-dev` and start a new session to get
the additional JDK.

Builds intentionally follow upstream versions for Go, Rust, uv, helper binaries,
Node package managers and browser tooling. Python, nvm and Helm defaults can be
overridden with `--build-arg PYTHON_VERSION=...`, `NVM_VERSION=...`, and
`HELM_VERSION=...`. Rebuild to update baked tools; existing user-selected runtime
versions remain selected. Pin upstream images and tool versions before requiring
reproducible releases. Browsers and native build tools make `dev` substantially
larger than `base`.

## Usage

From the root of a repository:

```sh
agent claude
agent codex
agent gemini --image base
agent claude --git rw      # permit staging, commits and branches
agent bash --image dev
```

`agent codex` automatically passes
`--dangerously-bypass-approvals-and-sandbox`. Podman provides the isolation;
Codex can run commands, including Maven builds, without individual approvals or
an additional command sandbox. This also applies to `agent codex -- resume --last`.
Reinstall the launcher with `bash ./install.sh` after updating it, then start a
new container session; no image rebuild is needed for this change. Existing
sessions keep their original permission settings.

Read-only mounts still apply: use `agent codex --git rw` when you want staging,
commits, and other Git metadata writes. `cat`, `ls`, and `git diff` work with
the default read-only Git metadata mount.

Every project is mounted at `/workspace/<project-directory-name>`; the first
project is the container's working directory. With no `--project`, the launcher
uses the current directory. This keeps repository directories together and leaves
`/workspace` itself unmounted. For example, a project named `backend` starts at
`/workspace/backend`.

Mount multiple projects:

```sh
agent claude --project "$HOME/code/backend" --project "$HOME/code/shared-library"
agent codex --project . --project ../common -- --help
```

Directory names must be distinct across projects. If two selected paths have
identical final directory names, the launcher exits with an error rather than
silently mounting one over the other. No project files are copied into the
container; the bind mounts still write directly to their host directories.

## Maven cache and VPN connectivity

When using `--image dev` (the default), the launcher mounts a named
`agent-maven-cache` volume at `/home/agent/.m2/repository`. This is **shared
between all agent CLIs and projects**, survives container removal, and is
separate from the host's `~/.m2` directory. It is **not** mounted under
`/workspace`; the project folder should not gain a `.m2` cache from this mount.
The `base` image does not mount it. If a project still produces a `.m2` folder,
check project-specific Maven configuration or the invoked build command.

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
- The Maven repository volume is shared among development agent sessions, including
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

## Back up and restore agent volumes

Close agent sessions and stop other containers writing to agent volumes before
backing up. Run `task backup` to export the existing agent home volumes and
shared Maven cache. The task prints the path to a new, private backup directory
in your home folder. Set `BACKUP_DIR` to choose a different new directory.
The archives can contain credentials and session history.

```sh
task backup
task restore BACKUP_DIR="$HOME/podman-volume-backup-YYYYMMDD-HHMMSS" PODMAN_CONNECTION=agent-200
```

Both tasks accept `PODMAN_CONNECTION` to select a named connection. Restore
checks every archived volume name on that connection and aborts before
creating anything if any target already exists, even if it is empty. Run
restore before starting agents on the new machine.
