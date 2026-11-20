#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

podman_cmd=(podman)
if [[ -n ${PODMAN_CONNECTION:-} ]]; then
  podman_cmd+=(--connection "$PODMAN_CONNECTION")
fi

backup_dir=${BACKUP_DIR:-}
case "$1" in
  backup)
    names=$("${podman_cmd[@]}" volume ls --format '{{.Name}}')
    volumes=()
    while IFS= read -r name; do
      case "$name" in
        agent-home-claude|agent-home-codex|agent-home-gemini|agent-home-bash|agent-maven-cache)
          volumes+=("$name")
          ;;
      esac
    done <<< "$names"
    (( ${#volumes[@]} > 0 )) || fail "No agent volumes found on the selected connection."

    umask 077
    backup_dir=${backup_dir:-"$HOME/podman-volume-backup-$(date +%Y%m%d-%H%M%S)"}
    mkdir -- "$backup_dir"
    for name in "${volumes[@]}"; do
      printf 'Backing up %s\n' "$name"
      "${podman_cmd[@]}" volume export "$name" > "$backup_dir/$name.tar"
      tar -tf "$backup_dir/$name.tar" > /dev/null
    done
    printf '%s\n' "${volumes[@]}" > "$backup_dir/.complete"
    printf 'Backup saved in %s\n' "$backup_dir"
    ;;
  restore)
    [[ -n $backup_dir ]] || fail "Set BACKUP_DIR to the backup folder."
    [[ -s $backup_dir/.complete ]] || fail "No completed backup found in $backup_dir."

    volumes=()
    while IFS= read -r name; do
      case "$name" in
        agent-home-claude|agent-home-codex|agent-home-gemini|agent-home-bash|agent-maven-cache) ;;
        *) fail "Unexpected volume name in backup: $name" ;;
      esac
      if "${podman_cmd[@]}" volume exists "$name"; then
        fail "Volume already exists: $name. Restore stopped before creating any volumes."
      else
        status=$?
        [[ $status == 1 ]] || fail "Could not check whether $name exists (Podman exit $status)."
      fi
      tar -tf "$backup_dir/$name.tar" > /dev/null
      volumes+=("$name")
    done < "$backup_dir/.complete"

    for name in "${volumes[@]}"; do
      printf 'Restoring %s\n' "$name"
      "${podman_cmd[@]}" volume create "$name" > /dev/null
      "${podman_cmd[@]}" volume import "$name" - < "$backup_dir/$name.tar"
    done
    ;;
  *) fail "Usage: $0 {backup|restore}" ;;
esac
