#!/bin/bash
# Quick check of OpenSearch status

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get OpenSearch EC2 instance ID"
  exit 1
fi

echo "=== Checking OpenSearch Status ==="
echo "Instance ID: $INSTANCE_ID"
echo ""

# Send command and wait for it
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== Docker Status ===\"",
    "sudo systemctl is-active docker || echo \"Docker not active\"",
    "echo \"\"",
    "echo \"=== OpenSearch Container ===\"",
    "sudo docker ps -a --filter name=opensearch --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\" || echo \"No container found\"",
    "echo \"\"",
    "echo \"=== OpenSearch Logs (last 20 lines) ===\"",
    "sudo docker logs opensearch --tail 20 2>&1 || echo \"No logs available\"",
    "echo \"\"",
    "echo \"=== Port 9200 Check ===\"",
    "sudo ss -tlnp | grep 9200 || echo \"Port 9200 not listening\"",
    "echo \"\"",
    "echo \"=== Health Check ===\"",
    "curl -s -m 5 http://localhost:9200/_cluster/health 2>&1 || echo \"Connection failed\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting 15 seconds for command to complete..."
sleep 15

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

STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'Status' \
  --output text 2>/dev/null)

if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
  echo "$OUTPUT"
  if [ -n "$ERRORS" ]; then
    echo ""
    echo "=== Errors ==="
    echo "$ERRORS"
  fi
else
  echo "Command still running. Status: $STATUS"
  echo "Check manually with:"
  echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID"
fi
