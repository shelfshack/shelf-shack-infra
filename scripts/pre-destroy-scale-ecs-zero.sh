#!/usr/bin/env bash
# Scale ECS service to 0 before terraform destroy so destroy doesn't get stuck
# waiting for tasks to drain. Run this, then run: terraform destroy -var-file=terraform.tfvars -auto-approve
#
# Usage: ./scripts/pre-destroy-scale-ecs-zero.sh [dev|prod]

set -e

ENVIRONMENT="${1:-dev}"
PROJECT="shelfshack"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${PROJECT}-${ENVIRONMENT}-cluster"
SERVICE="${PROJECT}-${ENVIRONMENT}-service"

echo "========================================="
echo "Scale ECS to 0 before destroy"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "Cluster:     $CLUSTER"
echo "Service:     $SERVICE"
echo "Region:      $REGION"
echo "========================================="

# Check if service exists
if ! aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
  echo "Service $SERVICE not found or not ACTIVE. Proceeding (terraform destroy will handle it)."
  exit 0
fi

echo "Setting desired count to 0..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --desired-count 0 \
  --region "$REGION" \
  --query 'service.{desiredCount:desiredCount,runningCount:runningCount}' \
  --output table

echo "Waiting for running count to reach 0 (may take 1-3 minutes)..."
for i in {1..36}; do
  RUNNING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
  if [ "$RUNNING" = "0" ]; then
    echo "Running count is 0. Safe to run terraform destroy."
    exit 0
  fi
  echo "  Running tasks: $RUNNING (waiting ${i}0s)..."
  sleep 10
done

echo "WARNING: Running count did not reach 0 after 6 minutes. You can still run terraform destroy; it may take longer."
exit 0
