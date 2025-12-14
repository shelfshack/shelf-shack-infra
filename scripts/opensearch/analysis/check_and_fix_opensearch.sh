#!/bin/bash
set -e

echo "=== COMPREHENSIVE OPENSEARCH FIX ==="
echo ""

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: Could not get instance ID"
  exit 1
fi

echo "Instance ID: $INSTANCE_ID"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

echo "1. Checking if security is disabled in Terraform..."
if grep -q "opensearch_ec2_security_disabled.*=.*true" terraform.tfvars 2>/dev/null; then
  echo "   ✓ Security is DISABLED (no password needed)"
  SECURITY_DISABLED=true
elif grep -q "opensearch_ec2_security_disabled.*=.*false" terraform.tfvars 2>/dev/null; then
  echo "   ✗ Security is ENABLED (password required)"
  SECURITY_DISABLED=false
else
  echo "   ⚠️  Not set in tfvars, using default (false = security enabled)"
  SECURITY_DISABLED=false
fi

echo ""
echo "2. Checking ECS environment variables..."
CLUSTER=$(terraform output -raw cluster_name 2>/dev/null)
SERVICE=$(terraform output -raw service_name 2>/dev/null)
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text 2>/dev/null)

OPENSEARCH_USERNAME=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_USERNAME`].value' --output text 2>/dev/null)
OPENSEARCH_PASSWORD=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_PASSWORD`].value' --output text 2>/dev/null)

echo "   OPENSEARCH_USERNAME: ${OPENSEARCH_USERNAME:-NOT SET}"
echo "   OPENSEARCH_PASSWORD: ${OPENSEARCH_PASSWORD:+SET (hidden)}"

if [ "$SECURITY_DISABLED" = "false" ] && [ -z "$OPENSEARCH_USERNAME" ]; then
  echo "   ⚠️  WARNING: Security enabled but credentials not set in ECS!"
fi

echo ""
echo "3. Attempting to check container status via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo \"=== DOCKER STATUS ===\"; sudo docker ps -a; echo \"\n=== PORT 9200 ===\"; sudo netstat -tlnp 2>/dev/null | grep 9200 || echo \"Port 9200 not listening\"; echo \"\n=== DOCKER LOGS (last 30) ===\"; sudo docker logs opensearch --tail 30 2>&1 || echo \"Container not found or cannot get logs\""]' \
  --output-s3-bucket-name "rentify-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null)

if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "None" ]; then
  echo "   Command sent: $COMMAND_ID"
  echo "   Waiting 10 seconds..."
  sleep 10
  echo ""
  echo "   OUTPUT:"
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null || echo "   Error getting output"
  echo ""
  echo "   ERRORS:"
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'StandardErrorContent' \
    --output text 2>/dev/null || echo "   No errors"
else
  echo "   ⚠️  Could not send SSM command"
fi

echo ""
echo "4. RECOMMENDED FIXES:"
echo ""
if [ "$SECURITY_DISABLED" = "false" ] && [ -z "$OPENSEARCH_USERNAME" ]; then
  echo "   FIX 1: Add opensearch_ec2_security_disabled = true to terraform.tfvars"
  echo "          OR set opensearch_ec2_admin_password in terraform.tfvars"
fi
echo ""
echo "   FIX 2: If container is not running, recreate instance:"
echo "          terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
echo "          terraform apply -var-file=terraform.tfvars"
echo ""
echo "   FIX 3: Restart ECS service to pick up new environment variables:"
echo "          aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment"

