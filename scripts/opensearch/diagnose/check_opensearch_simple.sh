#!/bin/bash
# Simple check script that handles the instance ID correctly

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev" || exit 1

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [[ "$INSTANCE_ID" == *"Warning"* ]] || [[ "$INSTANCE_ID" == *"No outputs"* ]]; then
  echo "Error: Could not get instance ID. Make sure terraform has been applied in envs/dev."
  echo "Trying to get it from AWS directly..."
  # Try to get it from AWS
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=shelfshack-dev-opensearch-ec2" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null)
  
  if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "ERROR: Could not find OpenSearch EC2 instance"
    exit 1
  fi
  echo "Found instance via AWS: $INSTANCE_ID"
fi

echo "OpenSearch EC2 Instance ID: $INSTANCE_ID"
echo ""

# Check if instance is running
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null)

if [ "$INSTANCE_STATE" != "running" ]; then
  echo "⚠️  Instance is not running. State: $INSTANCE_STATE"
  exit 1
fi

echo "✅ Instance is running"
echo ""

# Get OpenSearch endpoint
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null || echo "")
if [ -z "$OPENSEARCH_IP" ]; then
  OPENSEARCH_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text 2>/dev/null)
fi

echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

# Check container via SSM
echo "Checking OpenSearch container status..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo docker ps -a | grep opensearch || echo \"No opensearch container found\""]' \
  --query 'Command.CommandId' \
  --output text 2>/dev/null)

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "None" ]; then
  echo "⚠️  Could not send SSM command"
  exit 1
fi

sleep 3

OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null)

if [ -z "$OUTPUT" ]; then
  echo "⚠️  No output from SSM command"
  exit 1
fi

echo "$OUTPUT"
echo ""

# Check if container is running
if echo "$OUTPUT" | grep -q "Up"; then
  echo "✅ OpenSearch container is running"
else
  echo "❌ OpenSearch container is NOT running"
  echo ""
  echo "To fix, run:"
  echo "  ../../scripts/opensearch/fix/ensure_opensearch_running.sh"
fi
