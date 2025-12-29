#!/bin/bash
# Script to import existing production resources into Terraform state
# Usage: ./scripts/import-prod-resources.sh
#
# This script imports resources that already exist in AWS but are not in Terraform state.
# Run this once before your first terraform apply for prod.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$PROJECT_ROOT/envs/prod"

if [ ! -d "$ENV_DIR" ]; then
  echo "Error: Environment directory not found: $ENV_DIR"
  exit 1
fi

cd "$ENV_DIR"

# Source terraform.tfvars to get resource names
PROJECT=$(grep -E '^\s*project\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "shelfshack")
ENVIRONMENT=$(grep -E '^\s*environment\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "prod")
DEPLOY_ROLE_NAME=$(grep -E '^\s*deploy_role_name\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "${PROJECT}DeployRole")

LOCAL_NAME="${PROJECT}-${ENVIRONMENT}"

echo "=========================================="
echo "Importing Production Resources"
echo "=========================================="
echo "Project: $PROJECT"
echo "Environment: $ENVIRONMENT"
echo "Local Name: $LOCAL_NAME"
echo ""

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
  echo "Initializing Terraform..."
  terraform init >/dev/null 2>&1 || true
fi

# Function to safely import a resource
import_resource() {
  local resource_address=$1
  local resource_id=$2
  local resource_name=$3
  
  echo -n "Importing $resource_name... "
  
  # Check if already in state
  if terraform state list 2>/dev/null | grep -qE "^${resource_address}(\[0\])?$"; then
    echo "✓ Already in state"
    return 0
  fi
  
  # Attempt import
  if terraform import "$resource_address" "$resource_id" >/dev/null 2>&1; then
    echo "✓ Success"
    return 0
  else
    # Check if error is because it's already in state (different format)
    if terraform state list 2>/dev/null | grep -qE "${resource_address}"; then
      echo "✓ Already in state (different format)"
      return 0
    else
      echo "✗ Failed (may not exist or different ID format)"
      return 1
    fi
  fi
}

# 1. Import Deploy Role
echo ""
echo "1. IAM Roles"
import_resource "aws_iam_role.deploy_role" "$DEPLOY_ROLE_NAME" "Deploy Role ($DEPLOY_ROLE_NAME)" || true

# 2. Import ECR Repository
echo ""
echo "2. ECR Repository"
import_resource "module.ecr.aws_ecr_repository.this" "${LOCAL_NAME}-repo" "ECR Repository (${LOCAL_NAME}-repo)" || true

# 3. Import OpenSearch EC2 IAM Role
echo ""
echo "3. OpenSearch EC2 IAM Role"
import_resource "module.opensearch_ec2[0].aws_iam_role.opensearch" "${LOCAL_NAME}-opensearch-ec2-role" "OpenSearch EC2 Role" || true

# 4. Import RDS DB Subnet Group
echo ""
echo "4. RDS DB Subnet Group"
import_resource "module.rds.aws_db_subnet_group.this" "${LOCAL_NAME}-db-subnets" "RDS DB Subnet Group" || true

# 5. Import DynamoDB Table
echo ""
echo "5. DynamoDB Table"
import_resource "module.websocket_lambda.aws_dynamodb_table.websocket_connections" "${LOCAL_NAME}-websocket-connections" "WebSocket Connections Table" || true

# 6. Import WebSocket Lambda IAM Role
echo ""
echo "6. WebSocket Lambda IAM Role"
import_resource "module.websocket_lambda.aws_iam_role.lambda_role" "${LOCAL_NAME}-websocket-lambda-role" "WebSocket Lambda Role" || true

echo ""
echo "=========================================="
echo "Import Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to verify the imports"
echo "2. Run 'terraform apply' to manage these resources"
echo ""
echo "Note: Some resources may need additional imports (like IAM role policies)."
echo "      If you see errors, check the resource IDs and import manually."

