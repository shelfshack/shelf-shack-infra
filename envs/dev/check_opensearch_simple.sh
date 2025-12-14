#!/bin/bash
# Simple check script that handles the instance ID correctly

cd "$(dirname "$0")" || exit 1

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [[ "$INSTANCE_ID" == *"Warning"* ]] || [[ "$INSTANCE_ID" == *"No outputs"* ]]; then
  echo "Error: Could not get instance ID. Make sure you're in envs/dev and terraform has been applied."
  echo "Trying to get it from AWS directly..."
  # Try to get it from AWS
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=rentify-dev-opensearch-ec2" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null)
  
  if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "Could not find instance. Please check manually."
    exit 1
  fi
fi

echo "Instance ID: $INSTANCE_ID"
echo ""

echo "Checking OpenSearch status..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== Container Status ===\"",
    "sudo docker ps -a --filter name=opensearch --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\"",
    "echo \"\"",
    "echo \"=== OpenSearch Health Check ===\"",
    "curl -s -m 5 http://localhost:9200/_cluster/health 2>&1 || echo \"Connection failed or not ready\"",
    "echo \"\"",
    "echo \"=== Port 9200 Status ===\"",
    "sudo ss -tlnp | grep 9200 || echo \"Port 9200 not listening\"",
    "echo \"\"",
    "echo \"=== Recent Logs (last 15 lines) ===\"",
    "sudo docker logs opensearch --tail 15 2>&1 || echo \"No logs available\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting 15 seconds for results..."
sleep 15

echo ""
echo "=== Results ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null

echo ""
ERRORS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null)

if [ -n "$ERRORS" ] && [ "$ERRORS" != "None" ]; then
  echo "=== Errors ==="
  echo "$ERRORS"
fi
