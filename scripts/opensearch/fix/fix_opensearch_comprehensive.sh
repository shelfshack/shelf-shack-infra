#!/bin/bash
# Comprehensive fix for OpenSearch - Senior Architect Approach

echo "=== OpenSearch Fix - Comprehensive Solution ==="
echo ""

# Analysis
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host)
INSTANCE_AGE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].LaunchTime' \
  --output text)

echo "Current State:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Private IP: $OPENSEARCH_IP"
echo "  Launched: $INSTANCE_AGE"
echo ""

# Check if instance is very new (< 5 minutes)
LAUNCH_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${INSTANCE_AGE%+*}" "+%s" 2>/dev/null || date -d "$INSTANCE_AGE" +%s 2>/dev/null)
CURRENT_EPOCH=$(date +%s)
AGE_SECONDS=$((CURRENT_EPOCH - LAUNCH_EPOCH))

if [ $AGE_SECONDS -lt 300 ]; then
  echo "⚠️  Instance is very new (< 5 minutes old)"
  echo "   User data script may still be running."
  echo "   Wait 2-3 more minutes, then check again."
  echo ""
fi

echo "=== Solution Options ==="
echo ""
echo "OPTION 1: Recreate Instance (Recommended)"
echo "  This ensures user data runs with latest configuration:"
echo "    terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
echo "    terraform apply -var-file=terraform.tfvars"
echo ""
echo "OPTION 2: Check User Data Logs (if SSM works)"
echo "  Connect via bastion or wait for SSM to reconnect"
echo ""
echo "OPTION 3: Verify from ECS Task"
echo "  Test connectivity from ECS to verify network path:"
echo "    ./test_from_ecs.sh"
echo ""

# Check if we can verify container status
echo "=== Verification Steps ==="
echo ""
echo "1. Wait 2-3 minutes if instance is new"
echo "2. Check ECS service logs for connection attempts"
echo "3. Verify security groups (already confirmed OK)"
echo "4. Test from ECS task if possible"
echo ""

echo "=== Recommended Action ==="
echo "Since SSM is not accessible, the most reliable fix is:"
echo ""
echo "  cd envs/dev"
echo "  terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
echo "  terraform apply -var-file=terraform.tfvars"
echo ""
echo "This will:"
echo "  ✓ Recreate instance with latest user data"
echo "  ✓ Use correct password (OpenSearch@2024!)"
echo "  ✓ Include improved error handling"
echo "  ✓ Auto-start OpenSearch container"
echo ""
echo "Wait 3-4 minutes after apply for OpenSearch to be ready."
