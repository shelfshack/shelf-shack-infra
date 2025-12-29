#!/bin/bash
# Script to import existing Amplify branch into Terraform state
# Usage: ./scripts/import-amplify-branch.sh <environment>
# Example: ./scripts/import-amplify-branch.sh dev

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$PROJECT_ROOT/envs/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
  echo "Error: Environment directory not found: $ENV_DIR"
  exit 1
fi

cd "$ENV_DIR"

# Source terraform.tfvars to get app_id and branch_name
# This is a simple parser - it looks for amplify_app_id and amplify_dev_branch_name or amplify_prod_branch_name
if [ "$ENVIRONMENT" = "dev" ]; then
  APP_ID=$(grep -E '^\s*amplify_app_id\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "")
  BRANCH_NAME=$(grep -E '^\s*amplify_dev_branch_name\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "develop")
  RESOURCE_NAME="development"
elif [ "$ENVIRONMENT" = "prod" ]; then
  APP_ID=$(grep -E '^\s*amplify_app_id\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "")
  BRANCH_NAME=$(grep -E '^\s*amplify_prod_branch_name\s*=' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d '"' || echo "main")
  RESOURCE_NAME="production"
else
  echo "Error: Unknown environment: $ENVIRONMENT (supported: dev, prod)"
  exit 1
fi

if [ -z "$APP_ID" ]; then
  echo "Warning: amplify_app_id not found in terraform.tfvars. Skipping import."
  exit 0
fi

echo "Checking if Amplify branch exists: $APP_ID/$BRANCH_NAME"

# Check if branch exists in AWS
if aws amplify get-branch --app-id "$APP_ID" --branch-name "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "Branch exists in AWS. Attempting to import into Terraform state..."
  
  # Check if already in state
  if terraform state list 2>/dev/null | grep -q "aws_amplify_branch.$RESOURCE_NAME\[0\]"; then
    echo "Branch is already in Terraform state. Skipping import."
    exit 0
  fi
  
  # Attempt import
  if terraform import "aws_amplify_branch.$RESOURCE_NAME[0]" "$APP_ID/$BRANCH_NAME" 2>&1; then
    echo "Successfully imported Amplify branch: $APP_ID/$BRANCH_NAME"
  else
    echo "Import failed (branch may already be in state or there was an error)"
    exit 0  # Don't fail the script - continue with apply
  fi
else
  echo "Branch does not exist in AWS. Terraform will create it on apply."
  exit 0
fi

