#!/bin/bash
# Get SSM command result

if [ -z "$1" ]; then
  echo "Usage: ./get_command_result.sh <COMMAND_ID>"
  echo "Example: ./get_command_result.sh 3f6ce4d2-2ae9-488d-8200-a33e06d4a108"
  exit 1
fi

INSTANCE_ID="i-0c05f4a5b9c91d484"
COMMAND_ID="$1"

echo "Getting result for command: $COMMAND_ID"
echo ""

# Poll until complete
for i in {1..20}; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")
  
  if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
    break
  fi
  echo -n "."
  sleep 2
done

echo ""
echo ""
echo "Status: $STATUS"
echo ""

OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null)

ERRORS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null)

if [ -n "$OUTPUT" ] && [ "$OUTPUT" != "None" ]; then
  echo "=== Output ==="
  echo "$OUTPUT"
fi

if [ -n "$ERRORS" ] && [ "$ERRORS" != "None" ]; then
  echo ""
  echo "=== Errors ==="
  echo "$ERRORS"
fi
