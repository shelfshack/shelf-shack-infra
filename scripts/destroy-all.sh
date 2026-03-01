#!/usr/bin/env bash
# Destroy ALL resources in the AWS environment for the given env (dev or prod):
# ECS, VPC (IGW, NAT, subnets, endpoints, etc.), RDS, Lambda, API Gateway (HTTP + WebSocket), and everything else.
# Avoids Terraform getting stuck by deleting ECS and VPC in AWS first, then removing them from state, then running destroy.
#
# Usage: ./scripts/destroy-all.sh [dev|prod] [--auto-approve]

set -e

ENVIRONMENT="${1:-}"
AUTO_APPROVE="${2:-}"

if [ -z "$ENVIRONMENT" ] || { [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; }; then
    echo "Usage: $0 <dev|prod> [--auto-approve]"
    echo "  Destroys all Terraform-managed resources: VPC, IGW, NAT, ECS, RDS, Lambda, API Gateway (HTTP + WebSocket), etc."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$REPO_ROOT/envs/$ENVIRONMENT"

# Region from tfvars
REGION="${AWS_REGION:-us-east-1}"
[ -f "$ENV_DIR/terraform.tfvars" ] && REGION=$(grep -E '^\s*aws_region\s*=' "$ENV_DIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | tr -d ' ') || true
REGION="${REGION:-us-east-1}"

CLUSTER="shelfshack-${ENVIRONMENT}-cluster"
SERVICE="shelfshack-${ENVIRONMENT}-service"

echo "========================================="
echo "DESTROY ALL – $ENVIRONMENT"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "Region:      $REGION"
echo "========================================="
echo ""

cd "$ENV_DIR" || exit 1

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    echo ""
fi

# --- 1) Amplify branch: remove from state (keep in AWS) ---
if [ "$ENVIRONMENT" = "dev" ]; then
    AMPLIFY_BRANCH_STATE="aws_amplify_branch.development[0]"
else
    AMPLIFY_BRANCH_STATE="aws_amplify_branch.production[0]"
fi
if terraform state list 2>/dev/null | grep -q "$AMPLIFY_BRANCH_STATE"; then
    echo "Removing Amplify branch from state (will be preserved in AWS)..."
    terraform state rm "$AMPLIFY_BRANCH_STATE" 2>/dev/null || true
    echo "✅ Amplify branch removed from state"
    echo ""
fi

# --- 2) ECS: force-delete in AWS, then remove from state ---
echo "--- ECS: force-delete in AWS ---"
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    SVC_STATUS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")
    if [ "$SVC_STATUS" = "ACTIVE" ]; then
        aws ecs delete-service --cluster "$CLUSTER" --service "$SERVICE" --region "$REGION" --force --output text
        echo "Waiting for ECS service to become INACTIVE (up to 3 min)..."
        for i in {1..18}; do
            SVC_STATUS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "INACTIVE")
            [ "$SVC_STATUS" = "INACTIVE" ] && break
            echo "  Status: $SVC_STATUS (${i}0s)..."
            sleep 10
        done
    fi
    aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION" --output text || true
    echo "ECS cluster delete requested."
else
    echo "ECS cluster not found or not ACTIVE; skipping."
fi
echo "Removing ECS and related data from Terraform state..."
terraform state rm 'module.ecs_service.aws_ecs_service.this' 2>/dev/null || true
terraform state rm 'module.ecs_service.aws_ecs_cluster.this' 2>/dev/null || true
terraform state rm 'data.external.ecs_task_public_ip[0]' 2>/dev/null || true
echo "✅ ECS state removed"
echo ""

# --- 3) VPC: get ID from state, force-delete in AWS, then remove networking from state ---
echo "--- VPC: force-delete in AWS (NAT, IGW, endpoints, ENIs, subnets, route tables, SGs, VPC) ---"
VPC_ID=$(terraform state show 'module.networking.aws_vpc.this[0]' 2>/dev/null | grep '^id ' | sed 's/^id *= *"\(.*\)"/\1/' | tr -d ' ' || true)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "null" ]; then
    "$SCRIPT_DIR/force-destroy-vpc.sh" "$ENVIRONMENT" "$VPC_ID" || true
    echo "Removing networking module from Terraform state..."
    terraform state rm 'module.networking' 2>/dev/null || true
    echo "✅ Networking state removed"
else
    echo "No VPC in state (or state empty); skipping VPC force-delete."
    # Still try to remove networking from state in case it's partially there
    terraform state rm 'module.networking' 2>/dev/null || true
fi
echo ""

# --- 4) Full Terraform destroy (RDS, Lambda, API Gateway HTTP + WebSocket, etc.) ---
echo "--- Terraform destroy (RDS, Lambda, API Gateway, WebSocket, ECR, secrets, etc.) ---"
if [ "$AUTO_APPROVE" = "--auto-approve" ]; then
    terraform destroy -refresh=false -var-file=terraform.tfvars -auto-approve
else
    echo "Run with --auto-approve to skip confirmation."
    terraform destroy -refresh=false -var-file=terraform.tfvars
fi

echo ""
echo "========================================="
echo "Destroy complete – $ENVIRONMENT"
echo "========================================="
echo "Verify: ./scripts/verify_destroy.sh $ENVIRONMENT"
echo ""
