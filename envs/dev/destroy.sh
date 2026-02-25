#!/bin/bash
set -euo pipefail

# Single command to destroy all Terraform resources
# This script uses Terraform itself to disable RDS deletion protection, then destroys everything

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if allow_destruction is set
if [ -z "${1:-}" ] || [ "$1" != "true" ]; then
  echo "ERROR: This script requires 'allow_destruction=true' as the first argument" >&2
  echo "" >&2
  echo "Usage: $0 true [db_master_password]" >&2
  echo "" >&2
  echo "Example:" >&2
  echo "  $0 true YOUR_PASSWORD" >&2
  echo "" >&2
  exit 1
fi

ALLOW_DESTRUCTION="$1"
DB_PASSWORD="${2:-YOUR_PASSWORD}"

echo "=========================================="
echo "Step 1: Updating RDS to disable deletion protection"
echo "=========================================="
# Use Terraform to update RDS deletion_protection to false
# This ensures Terraform manages the change properly
echo "Running terraform apply to disable RDS deletion protection..."
terraform apply \
  -target=module.rds.aws_db_instance.this[0] \
  -var-file=terraform.tfvars \
  -var="allow_destruction=$ALLOW_DESTRUCTION" \
  -var="db_master_password=$DB_PASSWORD" \
  -auto-approve

echo ""
echo "=========================================="
echo "Step 2: Removing destroy_protection from state"
echo "=========================================="
# Remove protection resource from state BEFORE destroy
# This must be done AFTER the RDS update to avoid it being recreated
if terraform state list 2>/dev/null | grep -q "null_resource.destroy_protection"; then
  echo "Removing null_resource.destroy_protection from state..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || \
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
  echo "✅ Protection resource removed from state"
else
  echo "✅ Protection resource not found in state (already removed)"
fi

echo ""
echo "=========================================="
echo "Step 3: Destroying all resources"
echo "=========================================="
# Now destroy everything - deletion protection is already disabled and protection resource is removed
terraform destroy \
  -var-file=terraform.tfvars \
  -var="allow_destruction=$ALLOW_DESTRUCTION" \
  -var="db_master_password=$DB_PASSWORD" \
  -auto-approve

# Final cleanup: Remove protection resource if it still exists (in case destroy was partially completed)
if terraform state list 2>/dev/null | grep -q "null_resource.destroy_protection"; then
  echo ""
  echo "Removing remaining protection resource from state..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || \
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✓✓✓ Destroy complete! All resources destroyed. ✓✓✓"
echo "=========================================="
