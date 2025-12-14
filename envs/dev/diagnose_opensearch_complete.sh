#!/bin/bash
# Comprehensive OpenSearch Diagnosis Script
# This script checks all aspects of the OpenSearch setup

set -e

echo "=========================================="
echo "COMPREHENSIVE OPENSEARCH DIAGNOSIS"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

# Get infrastructure details
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null || echo "NOT_FOUND")
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null || echo "NOT_FOUND")
CLUSTER=$(terraform output -raw cluster_name 2>/dev/null || echo "NOT_FOUND")
SERVICE=$(terraform output -raw service_name 2>/dev/null || echo "NOT_FOUND")

echo "1. INFRASTRUCTURE STATUS"
echo "   Instance ID: $INSTANCE_ID"
echo "   OpenSearch IP: $OPENSEARCH_IP"
echo "   ECS Cluster: $CLUSTER"
echo "   ECS Service: $SERVICE"
echo ""

if [ "$INSTANCE_ID" = "NOT_FOUND" ]; then
  echo "   ⚠️  ERROR: OpenSearch EC2 instance not found in Terraform state"
  echo "   Run: terraform apply -var-file=terraform.tfvars"
  exit 1
fi

# Check instance status
echo "2. EC2 INSTANCE STATUS"
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "UNKNOWN")
INSTANCE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "UNKNOWN")
echo "   State: $INSTANCE_STATE"
echo "   Private IP: $INSTANCE_IP"
if [ "$INSTANCE_STATE" != "running" ]; then
  echo "   ⚠️  WARNING: Instance is not running!"
fi
echo ""

# Check security groups
echo "3. SECURITY GROUP CONFIGURATION"
OPENSEARCH_SG=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)
echo "   OpenSearch SG: $OPENSEARCH_SG"

# Get ECS security group - try multiple methods
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text 2>/dev/null || echo "NOT_FOUND")

# Method 1: Try Terraform output (after adding it to outputs.tf)
ECS_SG=$(terraform output -raw service_security_group_id 2>/dev/null || echo "NOT_FOUND")

# Method 2: Get from ECS service directly (most reliable)
if [ "$ECS_SG" = "NOT_FOUND" ] || [ "$ECS_SG" = "None" ] || [ -z "$ECS_SG" ]; then
  ECS_SG=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
    --output text 2>/dev/null || echo "NOT_FOUND")
fi

# Method 3: Fallback to task definition
if [ "$ECS_SG" = "NOT_FOUND" ] || [ "$ECS_SG" = "None" ] || [ -z "$ECS_SG" ]; then
  if [ "$TASK_DEF" != "NOT_FOUND" ] && [ "$TASK_DEF" != "None" ]; then
    ECS_SG=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
      --query 'taskDefinition.networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
      --output text 2>/dev/null || echo "NOT_FOUND")
  fi
fi

if [ "$ECS_SG" = "NOT_FOUND" ] || [ "$ECS_SG" = "None" ] || [ -z "$ECS_SG" ]; then
  echo "   ECS SG: NOT_FOUND (could not determine)"
else
  echo "   ECS SG: $ECS_SG"
fi

# Check security group rules using describe-security-groups (more reliable)
echo "   Checking security group rules for port 9200..."
RULE_EXISTS=$(aws ec2 describe-security-groups --group-ids "$OPENSEARCH_SG" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`9200\` && ToPort==\`9200\` && IpProtocol==\`tcp\` && length(UserIdGroupPairs[?GroupId==\`$ECS_SG\`]) > \`0\`] | length(@)" \
  --output text 2>/dev/null || echo "0")

if [ "$RULE_EXISTS" = "0" ] || [ -z "$RULE_EXISTS" ]; then
  # Check if any rules exist on port 9200
  ANY_RULES=$(aws ec2 describe-security-groups --group-ids "$OPENSEARCH_SG" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`9200\` && ToPort==\`9200\` && IpProtocol==\`tcp\`] | length(@)" \
    --output text 2>/dev/null || echo "0")
  
  if [ "$ANY_RULES" = "0" ] || [ -z "$ANY_RULES" ]; then
    echo "   ⚠️  ERROR: No security group rules found for port 9200!"
    echo "   OpenSearch SG ($OPENSEARCH_SG) has no ingress rules on port 9200"
    echo "   Run: terraform apply to create the security group rules"
  elif [ "$ECS_SG" != "NOT_FOUND" ] && [ "$ECS_SG" != "None" ] && [ -n "$ECS_SG" ]; then
    echo "   ⚠️  WARNING: Rules exist on port 9200, but not from ECS SG ($ECS_SG)"
    echo "   This may indicate the security group rule was not created correctly"
    echo "   Check Terraform state: terraform state list | grep opensearch_from_ecs"
  else
    echo "   ⚠️  WARNING: Rules exist on port 9200, but ECS SG could not be determined"
  fi
else
  echo "   ✓ Security group rule exists from ECS SG ($ECS_SG) on port 9200"
fi
echo ""

# Check ECS environment variables
echo "4. ECS ENVIRONMENT VARIABLES"
if [ "$TASK_DEF" != "NOT_FOUND" ]; then
  OPENSEARCH_HOST=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
    --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_HOST`].value' \
    --output text 2>/dev/null || echo "NOT_SET")
  OPENSEARCH_PORT=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
    --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_PORT`].value' \
    --output text 2>/dev/null || echo "NOT_SET")
  OPENSEARCH_USERNAME=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
    --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_USERNAME`].value' \
    --output text 2>/dev/null || echo "NOT_SET")
  OPENSEARCH_PASSWORD=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
    --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_PASSWORD`].value' \
    --output text 2>/dev/null || echo "NOT_SET")
  OPENSEARCH_USE_SSL=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" \
    --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_USE_SSL`].value' \
    --output text 2>/dev/null || echo "NOT_SET")
  
  echo "   OPENSEARCH_HOST: $OPENSEARCH_HOST"
  echo "   OPENSEARCH_PORT: $OPENSEARCH_PORT"
  echo "   OPENSEARCH_USERNAME: $OPENSEARCH_USERNAME"
  echo "   OPENSEARCH_PASSWORD: ${OPENSEARCH_PASSWORD:+SET (hidden)}"
  echo "   OPENSEARCH_USE_SSL: $OPENSEARCH_USE_SSL"
  
  if [ "$OPENSEARCH_HOST" != "$OPENSEARCH_IP" ]; then
    echo "   ⚠️  WARNING: OPENSEARCH_HOST ($OPENSEARCH_HOST) != OpenSearch IP ($OPENSEARCH_IP)"
    echo "   ECS service may be using stale IP. Restart service to update."
  fi
else
  echo "   ⚠️  Could not get task definition"
fi
echo ""

# Check Terraform configuration
echo "5. TERRAFORM CONFIGURATION"
if grep -q "opensearch_ec2_security_disabled.*=.*true" terraform.tfvars 2>/dev/null; then
  echo "   ✓ Security DISABLED (no password needed)"
  SECURITY_DISABLED=true
elif grep -q "opensearch_ec2_security_disabled.*=.*false" terraform.tfvars 2>/dev/null; then
  echo "   ⚠️  Security ENABLED (password required)"
  SECURITY_DISABLED=false
else
  echo "   ⚠️  Not set in tfvars (default: false = security enabled)"
  SECURITY_DISABLED=false
fi

if grep -q "enable_opensearch_ec2.*=.*true" terraform.tfvars 2>/dev/null; then
  echo "   ✓ OpenSearch EC2 enabled"
else
  echo "   ⚠️  OpenSearch EC2 not explicitly enabled in tfvars"
fi
echo ""

# Try to check container status via SSM
echo "6. CONTAINER STATUS (via SSM)"
if [ "$INSTANCE_STATE" = "running" ]; then
  echo "   Sending SSM command to check container..."
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["echo \"=== DOCKER STATUS ===\"; sudo docker ps -a | grep opensearch || echo \"No opensearch container\"; echo \"\n=== PORT 9200 ===\"; sudo netstat -tlnp 2>/dev/null | grep 9200 || sudo ss -tlnp 2>/dev/null | grep 9200 || echo \"Port 9200 not listening\"; echo \"\n=== DOCKER LOGS (last 20) ===\"; sudo docker logs opensearch --tail 20 2>&1 || echo \"Cannot get logs\""]' \
    --output-s3-bucket-name "rentify-dev-logs" \
    --output-s3-key-prefix "ssm-commands" \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || echo "FAILED")
  
  if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "FAILED" ] && [ "$COMMAND_ID" != "None" ]; then
    echo "   Command ID: $COMMAND_ID"
    echo "   Waiting 8 seconds for command to complete..."
    sleep 8
    echo ""
    echo "   OUTPUT:"
    OUTPUT=$(aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text 2>/dev/null || echo "ERROR")
    echo "$OUTPUT"
    echo ""
    echo "   ERRORS:"
    ERRORS=$(aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardErrorContent' \
      --output text 2>/dev/null || echo "NONE")
    echo "$ERRORS"
  else
    echo "   ⚠️  Could not send SSM command"
    echo "   This may indicate:"
    echo "   - SSM agent not installed/configured"
    echo "   - Instance not accessible (no internet/VPC endpoints)"
    echo "   - IAM role missing SSM permissions"
  fi
else
  echo "   ⚠️  Instance not running, cannot check container"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "SUMMARY & RECOMMENDATIONS"
echo "=========================================="
echo ""

ISSUES=0

if [ "$INSTANCE_STATE" != "running" ]; then
  echo "❌ Issue: Instance not running"
  ISSUES=$((ISSUES + 1))
fi

if [ "$OPENSEARCH_HOST" != "$OPENSEARCH_IP" ] && [ "$OPENSEARCH_HOST" != "NOT_SET" ]; then
  echo "❌ Issue: ECS has stale OpenSearch IP"
  ISSUES=$((ISSUES + 1))
fi

if [ "$SECURITY_DISABLED" = "false" ] && [ "$OPENSEARCH_USERNAME" = "NOT_SET" ]; then
  echo "❌ Issue: Security enabled but credentials not set in ECS"
  ISSUES=$((ISSUES + 1))
fi

if [ "$RULE_EXISTS" = "0" ]; then
  echo "❌ Issue: Security group rule missing"
  ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
  echo "✓ All checks passed!"
  echo ""
  echo "If you're still seeing connection errors:"
  echo "1. Container may not be running - recreate instance:"
  echo "   terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
  echo "   terraform apply -var-file=terraform.tfvars"
  echo ""
  echo "2. Restart ECS service to pick up new IP:"
  echo "   aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment"
else
  echo ""
  echo "Found $ISSUES issue(s). Fix them and rerun this script."
fi

echo ""
echo "=========================================="

