#!/bin/bash

# Script to destroy Terraform infrastructure
# Usage: ./scripts/destroy.sh [dev|prod] [--auto-approve]

set -e

ENVIRONMENT="${1:-dev}"
AUTO_APPROVE="${2:-}"

if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "Error: Environment must be 'dev' or 'prod'"
    exit 1
fi

echo "========================================="
echo "Destroying Terraform Infrastructure"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "========================================="
echo ""

cd "$(dirname "$0")/../envs/$ENVIRONMENT" || exit 1

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    echo ""
fi

# Check if Amplify branch resource exists in state and remove it temporarily (dev or prod)
if [ "$ENVIRONMENT" = "dev" ]; then
    AMPLIFY_BRANCH_STATE="aws_amplify_branch.development[0]"
else
    AMPLIFY_BRANCH_STATE="aws_amplify_branch.production[0]"
fi
AMPLIFY_IN_STATE=false

if terraform state list 2>/dev/null | grep -q "$AMPLIFY_BRANCH_STATE"; then
    AMPLIFY_IN_STATE=true
    echo "Removing Amplify branch from Terraform state (will be preserved in AWS)..."
    terraform state rm "$AMPLIFY_BRANCH_STATE" 2>/dev/null || true
    echo "✅ Amplify branch removed from state (resource will remain in AWS)"
    echo ""
fi

# Run terraform destroy
if [ "$AUTO_APPROVE" == "--auto-approve" ]; then
    echo "Running terraform destroy with auto-approve..."
    terraform destroy -var-file=terraform.tfvars -auto-approve
else
    echo "Running terraform destroy (interactive mode)..."
    echo "You will be prompted to confirm destruction."
    echo "Note: Amplify branch will be preserved (excluded from destruction)"
    terraform destroy -var-file=terraform.tfvars
fi

# Re-import Amplify branch if it was in state (optional - only if you want Terraform to manage it again)
if [ "$AMPLIFY_IN_STATE" = true ]; then
    echo ""
    echo "ℹ️  Note: Amplify branch was excluded from destruction."
    echo "   If you want Terraform to manage it again, run:"
    echo "   terraform import $AMPLIFY_BRANCH_STATE <app_id>/<branch_name>"
    echo "   Or leave it unmanaged (it's managed by Git anyway)"
fi

echo ""
echo "========================================="
echo "Destroy Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Verify all resources are destroyed:"
echo "   ./scripts/verify_destroy.sh $ENVIRONMENT"
echo ""
echo "2. Clean up any remaining resources manually if needed:"
echo "   - Check for RDS snapshots"
echo "   - Check for CloudWatch log groups"
echo "   - Check for S3 buckets (if not managed by Terraform)"
echo "   - Check for Secrets Manager secrets (if manually created)"
echo ""

