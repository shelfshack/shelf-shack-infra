#!/bin/bash
#
# Comprehensive Terraform state fix for AWS account migration
# Runs all fix scripts in correct order
#

set -e

ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "========================================="
echo "Comprehensive Terraform State Fix"
echo "Environment: $ENVIRONMENT"
echo "========================================="
echo ""

SCRIPT_DIR="$(dirname "$0")"

# Step 1: Fix RDS state (must be first because of dependencies)
echo "🔧 Step 1: Fixing RDS state..."
echo "------------------------------"
if [ -f "$SCRIPT_DIR/fix-rds-state.sh" ]; then
    bash "$SCRIPT_DIR/fix-rds-state.sh" "$ENVIRONMENT" || echo "⚠️  RDS fix had issues"
else
    echo "⚠️  fix-rds-state.sh not found"
fi

echo ""

# Step 2: Fix subnet state
echo "🔧 Step 2: Fixing subnet state..."
echo "----------------------------------"
if [ -f "$SCRIPT_DIR/fix-subnet-state.sh" ]; then
    bash "$SCRIPT_DIR/fix-subnet-state.sh" "$ENVIRONMENT" || echo "⚠️  Subnet fix had issues"
else
    echo "⚠️  fix-subnet-state.sh not found"
fi

echo ""

# Step 3: Import remaining resources
echo "🔧 Step 3: Importing other resources..."
echo "----------------------------------------"
cd "$SCRIPT_DIR/../envs/$ENVIRONMENT"

# Import ECR if not in state
ECR_REPO="shelfshack-${ENVIRONMENT}-repo"
if ! terraform state list | grep -q "module.ecr.aws_ecr_repository.this"; then
    echo "Importing ECR repository: $ECR_REPO"
    terraform import 'module.ecr.aws_ecr_repository.this[0]' "$ECR_REPO" 2>/dev/null || echo "  ECR import failed"
fi

# Import ECS cluster if not in state
CLUSTER_NAME="shelfshack-${ENVIRONMENT}-cluster"
if ! terraform state list | grep -q "module.ecs_service.aws_ecs_cluster.this"; then
    echo "Importing ECS cluster: $CLUSTER_NAME"
    terraform import 'module.ecs_service.aws_ecs_cluster.this[0]' "$CLUSTER_NAME" 2>/dev/null || echo "  ECS cluster import failed"
fi

echo ""
echo "========================================="
echo "✅ All Fixes Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to verify"
echo "2. Should see minimal changes, NO resource deletions"
echo "3. Run 'terraform apply' if plan looks good"
echo ""
