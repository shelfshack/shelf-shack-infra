#!/bin/bash
# Finish prod cleanup after RDS finishes deleting

set -e

VPC_ID="vpc-0e5f68b99c41b1404"

echo "=== Finishing Production Cleanup ==="
echo ""

# Check if RDS is still deleting
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier shelfshack-prod-postgres --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "deleted")
if [ "$RDS_STATUS" == "deleting" ]; then
    echo "⚠️  RDS is still deleting. Please wait 5-10 minutes and run this script again."
    exit 0
fi

echo "✓ RDS has finished deleting"
echo ""

# Delete RDS Subnet Group
echo "Deleting RDS Subnet Group..."
aws rds delete-db-subnet-group --db-subnet-group-name shelfshack-prod-db-subnets 2>/dev/null && echo "  ✓ Deleted" || echo "  ⚠ Already deleted or not found"
echo ""

# Delete RDS Security Group
echo "Deleting RDS Security Group..."
aws ec2 delete-security-group --group-id sg-03e8818b302b323f8 2>/dev/null && echo "  ✓ Deleted" || echo "  ⚠ Already deleted or not found"
echo ""

# Wait a bit for network interfaces to release
echo "Waiting for network interfaces to release..."
sleep 10

# Delete remaining network interfaces
echo "Deleting remaining network interfaces..."
for eni in $(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null); do
    if [ -n "$eni" ] && [ "$eni" != "None" ]; then
        aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null && echo "  ✓ Deleted ENI: $eni" || echo "  ⚠ Could not delete: $eni"
    fi
done
echo ""

# Delete VPC
echo "Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null && echo "  ✓ VPC deleted successfully!" || echo "  ⚠ VPC still has dependencies"

echo ""
echo "=== Cleanup Complete ==="

