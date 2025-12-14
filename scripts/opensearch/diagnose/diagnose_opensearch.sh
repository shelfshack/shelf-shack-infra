#!/bin/bash
# Diagnose and fix OpenSearch on EC2

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get OpenSearch EC2 instance ID"
  exit 1
fi

echo "=== OpenSearch EC2 Diagnostic Script ==="
echo "Instance ID: $INSTANCE_ID"
echo ""

echo "Step 1: Checking instance status..."
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress]' \
  --output table

echo ""
echo "Step 2: Running diagnostic commands on instance..."
echo "This will check:"
echo "  - Docker service status"
echo "  - OpenSearch container status"
echo "  - OpenSearch logs"
echo "  - Port 9200 listening status"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== Docker Service Status ===\"",
    "sudo systemctl status docker --no-pager | head -10",
    "echo \"\"",
    "echo \"=== OpenSearch Container Status ===\"",
    "sudo docker ps -a | grep opensearch || echo \"No opensearch container found\"",
    "echo \"\"",
    "echo \"=== OpenSearch Container Logs (last 30 lines) ===\"",
    "sudo docker logs opensearch --tail 30 2>&1 || echo \"Container not found or no logs\"",
    "echo \"\"",
    "echo \"=== Port 9200 Status ===\"",
    "sudo netstat -tlnp | grep 9200 || sudo ss -tlnp | grep 9200 || echo \"Port 9200 not listening\"",
    "echo \"\"",
    "echo \"=== Testing OpenSearch Connection ===\"",
    "curl -s http://localhost:9200/_cluster/health 2>&1 || echo \"Connection failed\"",
    "echo \"\"",
    "echo \"=== User Data Log (last 20 lines) ===\"",
    "sudo tail -20 /var/log/user-data.log 2>&1 || echo \"No user-data.log found\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo ""
echo "Waiting 10 seconds for command to complete..."
sleep 10

echo ""
echo "=== Command Output ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text

echo ""
echo "=== Command Errors (if any) ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text

echo ""
echo "=== Next Steps ==="
echo "If OpenSearch is not running, you can:"
echo "1. Run: ./fix_opensearch.sh"
echo "2. Or connect manually: aws ssm start-session --target $INSTANCE_ID"
