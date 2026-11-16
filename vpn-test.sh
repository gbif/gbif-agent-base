#!/usr/bin/env bash
set -euo pipefail

# HTTP status codes (including authentication failures) confirm connectivity.
# No credentials are passed to the container or endpoint.
url=${1:-http://mq.gbif.org:15672/}

command -v curl >/dev/null || { echo 'curl is required on the host' >&2; exit 1; }
command -v podman >/dev/null || { echo 'podman is required' >&2; exit 1; }

probe() {
  local target=$1
  shift
  local status
  if status=$("$@" -sS -L -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 12 "$url"); then
    printf '%s: reachable (HTTP %s)\n' "$target" "$status"
  else
    printf '%s: FAILED (DNS, network, TLS or timeout)\n' "$target" >&2
    return 1
  fi
}

printf 'Checking endpoint: %s\n' "$url"
probe host curl || host_failed=1
probe container podman run --rm --pull=never \
  localhost/agent-base:latest curl || container_failed=1

if [[ ${host_failed:-0} == 1 || ${container_failed:-0} == 1 ]]; then
  echo 'If only the container fails, check Podman machine networking, VPN routes and DNS.' >&2
  exit 1
fi
