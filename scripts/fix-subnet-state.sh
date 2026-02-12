#!/bin/bash
#
# Fix Terraform state for networking resources after AWS account migration
# This script removes stale subnet references and imports existing resources
#

set -e

ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
VPC_ID="vpc-097e968d04d7c88ce"

echo "========================================="
echo "Fixing Terraform State for: $ENVIRONMENT"
echo "AWS Region: $AWS_REGION"
echo "VPC ID: $VPC_ID"
echo "========================================="
echo ""

# Change to environment directory
cd "$(dirname "$0")/../envs/$ENVIRONMENT"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

echo "Step 1: Remove stale networking resources from state"
echo "-----------------------------------------------------"

# Remove all subnet resources from state (they'll be re-imported or recreated)
echo "Removing public subnets..."
terraform state list | grep 'module.networking.aws_subnet.public' | while read resource; do
    echo "  Removing: $resource"
    terraform state rm "$resource" 2>/dev/null || echo "    Already removed or not found"
done

echo "Removing private subnets..."
terraform state list | grep 'module.networking.aws_subnet.private' | while read resource; do
    echo "  Removing: $resource"
    terraform state rm "$resource" 2>/dev/null || echo "    Already removed or not found"
done

# Remove route tables
echo "Removing route tables..."
terraform state list | grep 'module.networking.aws_route_table' | while read resource; do
    echo "  Removing: $resource"
    terraform state rm "$resource" 2>/dev/null || echo "    Already removed or not found"
done

# Remove route table associations
echo "Removing route table associations..."
terraform state list | grep 'module.networking.aws_route_table_association' | while read resource; do
    echo "  Removing: $resource"
    terraform state rm "$resource" 2>/dev/null || echo "    Already removed or not found"
done

echo ""
echo "Step 2: Import existing private subnets"
echo "----------------------------------------"

# Get existing private subnets
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" \
    --region "$AWS_REGION" \
    --query 'Subnets[*].SubnetId' \
    --output text)

if [ -n "$PRIVATE_SUBNETS" ]; then
    INDEX=0
    for SUBNET_ID in $PRIVATE_SUBNETS; do
        echo "  Importing private subnet [$INDEX]: $SUBNET_ID"
        terraform import "module.networking.aws_subnet.private[$INDEX]" "$SUBNET_ID" 2>/dev/null || echo "    Import failed, will be created"
        INDEX=$((INDEX + 1))
    done
else
    echo "  No existing private subnets found"
fi

echo ""
echo "Step 3: Check for public subnets"
echo "----------------------------------"

PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=public" \
    --region "$AWS_REGION" \
    --query 'Subnets[*].SubnetId' \
    --output text)

if [ -n "$PUBLIC_SUBNETS" ]; then
    INDEX=0
    for SUBNET_ID in $PUBLIC_SUBNETS; do
        echo "  Importing public subnet [$INDEX]: $SUBNET_ID"
        terraform import "module.networking.aws_subnet.public[$INDEX]" "$SUBNET_ID" 2>/dev/null || echo "    Import failed, will be created"
        INDEX=$((INDEX + 1))
    done
else
    echo "  No public subnets found - Terraform will create them"
fi

echo ""
echo "Step 4: Remove ECS service from state (will be recreated)"
echo "----------------------------------------------------------"
terraform state rm 'module.ecs_service.aws_ecs_service.this' 2>/dev/null || echo "  ECS service not in state or already removed"

echo ""
echo "========================================="
echo "✅ State Cleanup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to see what will be created/updated"
echo "2. Review the plan carefully"
echo "3. Run 'terraform apply' to create missing resources"
echo ""
echo "Expected changes:"
echo "  - Create 2 public subnets (10.0.0.0/24, 10.0.1.0/24)"
echo "  - Update existing private subnets (if needed)"
echo "  - Create route tables and associations"
echo "  - Recreate ECS service with correct subnet IDs"
echo ""
