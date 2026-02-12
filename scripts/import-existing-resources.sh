#!/bin/bash
#
# Import existing AWS resources into Terraform state
# This script imports resources from the current AWS account into Terraform
# to prevent Terraform from trying to destroy and recreate them
#
# Usage: ./import-existing-resources.sh <environment>
# Example: ./import-existing-resources.sh dev

set -e

ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="shelfshack"

echo "========================================="
echo "Importing Existing Resources for: $ENVIRONMENT"
echo "AWS Region: $AWS_REGION"
echo "========================================="
echo ""

# Change to environment directory
cd "$(dirname "$0")/../envs/$ENVIRONMENT"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

echo ""
echo "Step 1: Import VPC"
echo "-------------------"
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-vpc" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo "Found VPC: $VPC_ID"
    terraform import 'module.networking.aws_vpc.this[0]' "$VPC_ID" 2>/dev/null || echo "  Already imported or failed"
else
    echo "  No VPC found, skipping"
fi

echo ""
echo "Step 2: Import Internet Gateway"
echo "--------------------------------"
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text 2>/dev/null || echo "")

if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "Found Internet Gateway: $IGW_ID"
    terraform import 'module.networking.aws_internet_gateway.this[0]' "$IGW_ID" 2>/dev/null || echo "  Already imported or failed"
else
    echo "  No Internet Gateway found, skipping"
fi

echo ""
echo "Step 3: Import Public Subnets"
echo "------------------------------"
PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=public" \
    --region "$AWS_REGION" \
    --query 'Subnets[*].SubnetId' \
    --output text 2>/dev/null || echo "")

if [ -n "$PUBLIC_SUBNET_IDS" ]; then
    INDEX=0
    for SUBNET_ID in $PUBLIC_SUBNET_IDS; do
        echo "  Importing public subnet [$INDEX]: $SUBNET_ID"
        terraform import "module.networking.aws_subnet.public[$INDEX]" "$SUBNET_ID" 2>/dev/null || echo "    Already imported or failed"
        INDEX=$((INDEX + 1))
    done
else
    echo "  No public subnets found"
fi

echo ""
echo "Step 4: Import Private Subnets"
echo "-------------------------------"
PRIVATE_SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" \
    --region "$AWS_REGION" \
    --query 'Subnets[*].SubnetId' \
    --output text 2>/dev/null || echo "")

if [ -n "$PRIVATE_SUBNET_IDS" ]; then
    INDEX=0
    for SUBNET_ID in $PRIVATE_SUBNET_IDS; do
        echo "  Importing private subnet [$INDEX]: $SUBNET_ID"
        terraform import "module.networking.aws_subnet.private[$INDEX]" "$SUBNET_ID" 2>/dev/null || echo "    Already imported or failed"
        INDEX=$((INDEX + 1))
    done
else
    echo "  No private subnets found"
fi

echo ""
echo "Step 5: Import ECS Cluster"
echo "--------------------------"
CLUSTER_ARN=$(aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query "clusterArns[?contains(@, '${PROJECT_NAME}-${ENVIRONMENT}')]|[0]" \
    --output text 2>/dev/null || echo "")

if [ -n "$CLUSTER_ARN" ] && [ "$CLUSTER_ARN" != "None" ]; then
    echo "Found ECS Cluster: $CLUSTER_ARN"
    terraform import 'module.ecs_service.aws_ecs_cluster.this[0]' "$CLUSTER_ARN" 2>/dev/null || echo "  Already imported or failed"
else
    echo "  No ECS cluster found, skipping"
fi

echo ""
echo "Step 6: Import ECR Repository"
echo "------------------------------"
ECR_REPO_NAME="${PROJECT_NAME}-${ENVIRONMENT}-repo"
terraform import 'module.ecr.aws_ecr_repository.this[0]' "$ECR_REPO_NAME" 2>/dev/null || echo "  Already imported or failed"

echo ""
echo "========================================="
echo "✅ Import Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to verify no resources will be destroyed"
echo "2. If plan looks good, run 'terraform apply'"
echo ""
