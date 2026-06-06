#!/usr/bin/env bash
set -euo pipefail

#############################################
# link_flap_check.sh
#
#   Uses configurable topology paths and fabric-management access methods
#   to avoid embedding site-specific operational details.
#############################################

echo

#############################################
# Defaults / Config
#############################################

FABRIC_TOPOLOGY="${FABRIC_TOPOLOGY:-/path/to/topology.json}"
FABRIC_NAMESPACES="${FABRIC_NAMESPACES:-fabric-system fabric-services default}"
FABRIC_MANAGER_PATTERN="${FABRIC_MANAGER_PATTERN:-fabric-manager}"
FABRIC_SHELL_CMD="${FABRIC_SHELL_CMD:-}"

#############################################
# Help Menu
#############################################

print_help() {
cat <<EOF
link_flap_check.sh

Description:
  Queries a fabric topology file via a fabric management shell to:
    1) Identify conn_port values associated with given node xname(s)
    2) Run link-flap diagnostics for each discovered port

Usage:
  link_flap_check.sh <XNAME>
  link_flap_check.sh <comma-separated-xnames>
  link_flap_check.sh <space-separated-xnames>
  link_flap_check.sh -h | --help

Environment variables:
  FABRIC_TOPOLOGY
    Path to the topology JSON file inside the fabric management environment.
    Default: /path/to/topology.json

  FABRIC_NAMESPACES
    Space-separated Kubernetes namespaces to search for a fabric-manager pod.
    Default: fabric-system fabric-services default

  FABRIC_MANAGER_PATTERN
    Pod name pattern used to identify the fabric-manager pod.
    Default: fabric-manager

  FABRIC_SHELL_CMD
    Optional command used to enter the fabric management shell.
    If set, this is used before the kubectl fallback.
    Example: export FABRIC_SHELL_CMD="kubectl -n fabric-system exec -i <pod> -- sh"

Notes:
  • No files are left behind.
  • Duplicate ports are automatically filtered.
  • Requires: grep, cut, sort, sed, awk.
  • Requires either:
      - FABRIC_SHELL_CMD to be set, OR
      - kubectl access to a fabric-manager pod.

Output:
  ############################################################
  XNAME: <node>
  ############################################################
  == PORT: <port> ==
  show-flaps output

EOF
}

#############################################
# Helpers
#############################################

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -n "${TMP:-}" && -f "$TMP" ]] && rm -f "$TMP"
}

trap cleanup EXIT INT TERM

need_cmd grep
need_cmd cut
need_cmd sort
need_cmd sed
need_cmd awk

#############################################
# Help flag handling
#############################################

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

ARG="${1:-}"
[[ -n "$ARG" ]] || die "No target provided. Example: link_flap_check.sh \$XNAME"

#############################################
# Fabric management execution wrapper
#############################################

fmn() {
  if [[ -n "$FABRIC_SHELL_CMD" ]]; then
    # shellcheck disable=SC2086
    $FABRIC_SHELL_CMD
    return
  fi

  need_cmd kubectl

  local ns pod
  pod=""

  for ns in $FABRIC_NAMESPACES; do
    pod="$(
      kubectl -n "$ns" get pods 2>/dev/null |
        awk -v pattern="$FABRIC_MANAGER_PATTERN" '$0 ~ pattern && /Running/ {print $1; exit}'
    )"

    [[ -n "${pod:-}" ]] && break
  done

  [[ -n "${pod:-}" ]] || die "Could not find a running fabric-manager pod via kubectl."

  kubectl -n "$ns" exec -i "$pod" -- sh
}

#############################################
# Parse input xnames
#############################################

mapfile -t XNAMES < <(
  echo "$ARG" |
    sed 's/[[:space:]]\+/,/g; s/,,\+/,/g; s/^,//; s/,$//' |
    tr ',' '\n' |
    sed '/^[[:space:]]*$/d' |
    sort -u
)

[[ "${#XNAMES[@]}" -gt 0 ]] || die "No valid xnames parsed from input: $ARG"

#############################################
# Look up conn_port for a given xname
#############################################

ports_for_xname() {
  local xname="$1"

  echo "grep --color=never -i -h -C 3 \"$xname\" \"$FABRIC_TOPOLOGY\" 2>/dev/null" |
    fmn 2>/dev/null |
    grep -F 'conn_port' 2>/dev/null |
    cut -d '"' -f4 2>/dev/null |
    sed '/^[[:space:]]*$/d' |
    sort -u || true
}

#############################################
# Run fabric commands for a given port
#############################################

run_for_port() {
  local port="$1"

  echo
  echo "== PORT: $port =="
  echo
  echo "CMD: show-flaps -s 0 -l -N -t $port"
  echo

  echo "show-flaps -s 0 -l -N -t $port" |
    fmn 2>/dev/null || true

  echo
}

#############################################
# Main
#############################################

for x in "${XNAMES[@]}"; do
  echo "############################################################"
  echo "XNAME: $x"
  echo "############################################################"

  TMP="$(mktemp -t fabriccheck.XXXXXX)"

  ports_for_xname "$x" >"$TMP"

  if [[ ! -s "$TMP" ]]; then
    echo "No conn_port entries found for $x in topology data via fabric management shell."
    echo
    rm -f "$TMP"
    TMP=""
    continue
  fi

  while IFS= read -r port; do
    run_for_port "$port"
  done <"$TMP"

  rm -f "$TMP"
  TMP=""
done
