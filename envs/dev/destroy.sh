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
echo "Step 1: Removing destroy_protection from state (MUST be first)"
echo "=========================================="
# Remove protection resource from state FIRST to prevent it from blocking anything
# Try multiple variations to ensure it's removed
REMOVED=false
for resource_name in 'null_resource.destroy_protection[0]' 'null_resource.destroy_protection'; do
  if terraform state list 2>/dev/null | grep -q "$resource_name"; then
    echo "Removing $resource_name from state..."
    if terraform state rm "$resource_name" 2>/dev/null; then
      echo "✅ Removed $resource_name"
      REMOVED=true
    fi
  fi
done

if [ "$REMOVED" = true ]; then
  echo "✅ Protection resource removed from state"
else
  echo "✅ Protection resource not found in state (already removed or never existed)"
fi

# Verify it's actually gone
if terraform state list 2>/dev/null | grep -q "null_resource.destroy_protection"; then
  echo "⚠️  WARNING: Protection resource still in state after removal attempt!"
  echo "   Attempting force removal..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || true
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "Step 2: Updating RDS to disable deletion protection"
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

# Check again after apply - sometimes apply can recreate it
echo ""
echo "Verifying protection resource is still removed..."
if terraform state list 2>/dev/null | grep -q "null_resource.destroy_protection"; then
  echo "⚠️  Protection resource reappeared after RDS update. Removing again..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || \
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "Step 3: Final verification - ensure protection resource is removed"
echo "=========================================="
# One final check before destroy
if terraform state list 2>/dev/null | grep -q "null_resource.destroy_protection"; then
  echo "⚠️  Protection resource still exists! Force removing..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || \
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
  echo "✅ Force removal complete"
else
  echo "✅ Protection resource confirmed removed"
fi

echo ""
echo "=========================================="
echo "Step 4: Destroying all resources"
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
  echo "⚠️  Protection resource still exists after destroy. Removing..."
  terraform state rm 'null_resource.destroy_protection[0]' 2>/dev/null || \
  terraform state rm 'null_resource.destroy_protection' 2>/dev/null || true
  echo "✅ Cleanup complete"
fi

echo ""
echo "=========================================="
echo "✓✓✓ Destroy complete! All resources destroyed. ✓✓✓"
echo "=========================================="
