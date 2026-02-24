#!/usr/bin/env bash
# Runs terraform apply; on state lock error, force-unlocks and retries once.
# Usage: scripts/terraform-apply-with-unlock-retry.sh [extra terraform apply args...]
# Example: scripts/terraform-apply-with-unlock-retry.sh -auto-approve
# Example: scripts/terraform-apply-with-unlock-retry.sh -auto-approve -target=module.ecs_service

set -e

APPLY_ARGS=("$@")
APPLY_LOG=$(mktemp)
trap 'rm -f "$APPLY_LOG"' EXIT

set +e
if [[ ${#APPLY_ARGS[@]} -gt 0 ]]; then
  terraform apply "${APPLY_ARGS[@]}" 2>&1 | tee "$APPLY_LOG"
else
  terraform apply -auto-approve 2>&1 | tee "$APPLY_LOG"
fi
APPLY_EXIT=${PIPESTATUS[0]}
set -e

if [[ $APPLY_EXIT -eq 0 ]]; then
  exit 0
fi

# Check for state lock error
if ! grep -q "Error acquiring the state lock" "$APPLY_LOG"; then
  echo "Terraform apply failed (no state lock error). Exiting with code $APPLY_EXIT"
  exit $APPLY_EXIT
fi

# Parse lock ID (line after "Lock Info:" contains "ID: <uuid>")
LOCK_ID=$(grep -A 10 "Lock Info:" "$APPLY_LOG" | grep "ID:" | head -1 | sed 's/.*ID:[[:space:]]*//' | tr -d ' \r')

if [[ -z "$LOCK_ID" ]]; then
  echo "State lock error detected but could not parse Lock ID. Exiting."
  exit $APPLY_EXIT
fi

echo "State lock detected (ID: $LOCK_ID). Force-unlocking and retrying apply once..."
terraform force-unlock -force "$LOCK_ID"

if [[ ${#APPLY_ARGS[@]} -gt 0 ]]; then
  exec terraform apply "${APPLY_ARGS[@]}"
else
  exec terraform apply -auto-approve
fi
