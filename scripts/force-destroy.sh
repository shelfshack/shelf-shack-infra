#!/usr/bin/env bash
# Force-destroy: delete ECS service and cluster in AWS first, remove from state, then terraform destroy.
# Use when normal destroy gets stuck on ECS.
#
# Usage: ./scripts/force-destroy.sh [dev|prod] [--auto-approve]

set -e

ENVIRONMENT="${1:-dev}"
AUTO_APPROVE="${2:-}"

if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "Error: Environment must be 'dev' or 'prod'"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$REPO_ROOT/envs/$ENVIRONMENT"

# Region: from tfvars if present, else AWS_REGION, else us-east-1
if [ -f "$ENV_DIR/terraform.tfvars" ]; then
    REGION=$(grep -E '^\s*aws_region\s*=' "$ENV_DIR/terraform.tfvars" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | tr -d ' ')
fi
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
CLUSTER="shelfshack-${ENVIRONMENT}-cluster"
SERVICE="shelfshack-${ENVIRONMENT}-service"

echo "========================================="
echo "Force destroy (ECS deleted in AWS first)"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "Cluster:     $CLUSTER"
echo "Service:     $SERVICE"
echo "Region:      $REGION"
echo "========================================="
echo ""

cd "$ENV_DIR" || exit 1

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    echo ""
fi

# 1) Remove Amplify branch from state if present (keep branch in AWS)
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

# 2) Force-delete ECS service in AWS (--force = stop tasks immediately, don't wait for drain)
echo "Force-deleting ECS service in AWS..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")
if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo "Cluster not found or not ACTIVE (got: $CLUSTER_STATUS). Skipping AWS ECS delete."
else
    SVC_STATUS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")
    if [ "$SVC_STATUS" = "ACTIVE" ]; then
        aws ecs delete-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --region "$REGION" \
            --force \
            --output text
        echo "Waiting for service to become INACTIVE (up to 3 minutes)..."
        for i in {1..18}; do
            SVC_STATUS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "INACTIVE")
            if [ "$SVC_STATUS" = "INACTIVE" ]; then
                echo "Service is INACTIVE."
                break
            fi
            echo "  Status: $SVC_STATUS (${i}0s)..."
            sleep 10
        done
    else
        echo "Service not found or already inactive ($SVC_STATUS)."
    fi
    echo "Deleting ECS cluster in AWS..."
    aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION" --output text || true
    echo "Cluster delete requested."
fi
echo ""

# 3) Remove ECS service and cluster from Terraform state so destroy doesn't hang
echo "Removing ECS resources from Terraform state..."
terraform state rm 'module.ecs_service.aws_ecs_service.this' 2>/dev/null || true
terraform state rm 'module.ecs_service.aws_ecs_cluster.this' 2>/dev/null || true
echo "Removing external data source (depends on ECS) so destroy can run..."
terraform state rm 'data.external.ecs_task_public_ip[0]' 2>/dev/null || true
echo "✅ ECS and related state removed"
echo ""

# 4) Full terraform destroy (ECS cluster/service already gone in AWS and removed from state)
# -refresh=false avoids Terraform trying to refresh the deleted ECS resources from AWS
echo "Running terraform destroy..."
if [ "$AUTO_APPROVE" = "--auto-approve" ]; then
    terraform destroy -refresh=false -var-file=terraform.tfvars -auto-approve
else
    terraform destroy -refresh=false -var-file=terraform.tfvars
fi

echo ""
echo "========================================="
echo "Force destroy complete"
echo "========================================="
echo "Next: ./scripts/verify_destroy.sh $ENVIRONMENT"
echo ""
