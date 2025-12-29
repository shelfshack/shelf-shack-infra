#!/bin/bash
# Import existing prod resources into Terraform state
# Run this BEFORE terraform apply if resources already exist in AWS but not in state

set -e

cd "$(dirname "$0")/../envs/prod"

echo "=== Importing Existing Prod Resources into Terraform State ==="
echo ""

# Initialize Terraform if needed
terraform init -upgrade

echo ""
echo "1. Importing RDS DB Subnet Group..."
terraform import module.rds.aws_db_subnet_group.this shelfshack-prod-db-subnets 2>&1 || echo "   (may already be in state or doesn't exist)"

echo ""
echo "2. Importing RDS Instance..."
terraform import module.rds.aws_db_instance.this shelfshack-prod-postgres 2>&1 || echo "   (may already be in state or doesn't exist)"

echo ""
echo "3. Importing VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=shelfshack-prod-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  terraform import module.networking.aws_vpc.this[0] "$VPC_ID" 2>&1 || echo "   (may already be in state)"
fi

echo ""
echo "4. Importing Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
  terraform import module.networking.aws_internet_gateway.this[0] "$IGW_ID" 2>&1 || echo "   (may already be in state)"
fi

echo ""
echo "5. Importing Subnets..."
# Import public subnets
idx=0
for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=public" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
  terraform import "module.networking.aws_subnet.public[\"$idx\"]" "$subnet" 2>&1 || echo "   (may already be in state)"
  ((idx++))
done

# Import private subnets
idx=0
for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
  terraform import "module.networking.aws_subnet.private[\"$idx\"]" "$subnet" 2>&1 || echo "   (may already be in state)"
  ((idx++))
done

echo ""
echo "=== Import Complete ==="
echo ""
echo "Now run: terraform plan"
echo "Then: terraform apply"
