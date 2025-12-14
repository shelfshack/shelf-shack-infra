#!/bin/bash
set -e

echo "=== FINAL OPENSEARCH FIX ==="
echo ""

# Check current configuration
echo "1. Checking Terraform configuration..."
if ! grep -q "opensearch_ec2_security_disabled" terraform.tfvars 2>/dev/null; then
  echo "   ⚠️  opensearch_ec2_security_disabled not set in terraform.tfvars"
  echo "   Adding: opensearch_ec2_security_disabled = true"
  echo "" >> terraform.tfvars
  echo "# OpenSearch EC2 Configuration" >> terraform.tfvars
  echo "opensearch_ec2_security_disabled = true" >> terraform.tfvars
  echo "   ✓ Added to terraform.tfvars"
else
  echo "   ✓ Already configured"
fi

echo ""
echo "2. Checking if enable_opensearch_ec2 is set..."
if ! grep -q "enable_opensearch_ec2" terraform.tfvars 2>/dev/null; then
  echo "   ⚠️  enable_opensearch_ec2 not set"
  echo "   Adding: enable_opensearch_ec2 = true"
  echo "enable_opensearch_ec2 = true" >> terraform.tfvars
  echo "   ✓ Added to terraform.tfvars"
else
  echo "   ✓ Already configured"
fi

echo ""
echo "3. RECOMMENDED ACTIONS:"
echo ""
echo "   Step 1: Recreate the OpenSearch EC2 instance with improved user_data:"
echo "   cd envs/dev"
echo "   terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
echo "   terraform apply -var-file=terraform.tfvars"
echo ""
echo "   Step 2: Wait 5-8 minutes for:"
echo "   - Instance creation (2 min)"
echo "   - User data execution (2-3 min)"
echo "   - OpenSearch initialization (1-2 min)"
echo ""
echo "   Step 3: Restart ECS service to pick up any changes:"
echo "   aws ecs update-service --cluster rentify-dev-cluster --service rentify-dev-service --force-new-deployment"
echo ""
echo "   Step 4: Monitor logs:"
echo "   aws logs tail /ecs/rentify-dev --follow"

