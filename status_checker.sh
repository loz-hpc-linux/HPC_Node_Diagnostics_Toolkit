#!/bin/bash

# ----------------------------------------
# status_checker.sh - Scheduler & system-state checker for a given SLOT
# ----------------------------------------

ENV_SETUP_SCRIPT="${ENV_SETUP_SCRIPT:-setup_env.sh}"
SCHEDULER_HELPER="${SCHEDULER_HELPER:-/opt/hpc-tools/lib/scheduler.sh}"

# Help Menu
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo -e "\nUsage: ./status_check.sh <SLOT>\n"
  echo "Description:"
  echo "  Checks scheduler node status and system state for all nodes in the given SLOT."
  echo
  echo "Requirements:"
  echo "  - Run ${ENV_SETUP_SCRIPT} first to set the following variables:"
  echo "      \$CLUSTER_NAME, \$NODES_XNAME, \$SLOT"
  echo "  - Scheduler output is fetched from the correct access node via SSH."
  echo
  echo "Example:"
  echo "  ./status_check.sh x9000c3s0"
  exit 0
fi

# SLOT Input
SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Error: SLOT argument missing."
  echo "Run './status_check.sh --help' for usage."
  exit 1
fi

# Required environment variables
REQUIRED_VARS=(CLUSTER_NAME NODES_XNAME SLOT)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Environment variable \$$var is not set."
    echo "Please run ${ENV_SETUP_SCRIPT} first."
    exit 1
  fi
done

if [[ ! -f "$SCHEDULER_HELPER" ]]; then
  echo "Error: Required file 'scheduler.sh' not found at $SCHEDULER_HELPER"
  exit 1
fi

# Start Check
echo -e "\nChecking status for SLOT: $SLOT"
echo "------------------------------------------"

# Scheduler Output
echo -e "\nScheduler Status:"
echo -e "Querying scheduler for nodes: $NODES_XNAME"
echo
source "$SCHEDULER_HELPER"
pbs | grep "$SLOT"
echo

# System State Output
echo -e "\nSystem State:"
sat status --filter xname="${SLOT}b*" --fields xname,aliases,role,subrole,state,enabled,net,boot,desired,configuration

echo -e "\nDone.\n"
