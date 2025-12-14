#!/bin/bash
# Final improved check script

INSTANCE_ID="i-0c05f4a5b9c91d484"

echo "=== OpenSearch Status Check ==="
echo "Instance: $INSTANCE_ID"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== Docker Container ===\"",
    "sudo docker ps -a --filter name=opensearch --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\" || echo \"No container found\"",
    "echo \"\"",
    "echo \"=== OpenSearch Health ===\"",
    "curl -s -m 5 http://localhost:9200/_cluster/health 2>&1 || echo \"Connection failed\"",
    "echo \"\"",
    "echo \"=== Port 9200 ===\"",
    "sudo ss -tlnp 2>/dev/null | grep 9200 || sudo netstat -tlnp 2>/dev/null | grep 9200 || echo \"Port not listening\"",
    "echo \"\"",
    "echo \"=== Container Logs (last 20 lines) ===\"",
    "sudo docker logs opensearch --tail 20 2>&1 || echo \"No logs\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting 30 seconds for command to complete..."
sleep 30

# Poll until complete
for i in {1..10}; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")
  
  if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
    break
  fi
  echo -n "."
  sleep 3
done

echo ""
echo ""
echo "=== Results ==="
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
  echo "$OUTPUT"
else
  echo "No output received. Command status: $STATUS"
  echo "Try checking manually or wait longer."
fi

if [ -n "$ERRORS" ] && [ "$ERRORS" != "None" ]; then
  echo ""
  echo "=== Errors ==="
  echo "$ERRORS"
fi

echo ""
echo "=== If container is not running, restart it with: ==="
echo "  ./fix_opensearch_remote.sh"
