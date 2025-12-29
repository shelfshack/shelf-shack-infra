#!/bin/bash
# Complete cleanup script for production environment
# This will delete ALL resources in the prod environment

set -e

echo "=========================================="
echo "Complete Production Environment Cleanup"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will DELETE ALL production resources!"
echo "   Press Ctrl+C within 10 seconds to cancel..."
sleep 10
echo ""

cd "$(dirname "$0")/../envs/prod"

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_id=$2
    local check_command=$3
    
    echo "Waiting for $resource_type ($resource_id) to finish deleting..."
    while eval "$check_command" 2>/dev/null | grep -q "deleting\|DRAINING\|shutting"; do
        echo "  Still deleting, waiting 30 seconds..."
        sleep 30
    done
    echo "  ✓ $resource_type deleted"
}

# 1. Wait for RDS to finish deleting
if aws rds describe-db-instances --db-instance-identifier shelfshack-prod-postgres --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null | grep -q "deleting"; then
    wait_for_deletion "RDS Instance" "shelfshack-prod-postgres" \
        "aws rds describe-db-instances --db-instance-identifier shelfshack-prod-postgres --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null"
fi

# 2. Wait for ECS service to finish deleting
if aws ecs describe-services --cluster shelfshack-prod-cluster --services shelfshack-prod-service --query 'services[0].status' --output text 2>/dev/null | grep -qE "ACTIVE|DRAINING"; then
    wait_for_deletion "ECS Service" "shelfshack-prod-service" \
        "aws ecs describe-services --cluster shelfshack-prod-cluster --services shelfshack-prod-service --query 'services[0].status' --output text 2>/dev/null"
fi

# 3. Delete ECS cluster
echo ""
echo "Deleting ECS cluster..."
aws ecs delete-cluster --cluster shelfshack-prod-cluster 2>&1 | grep -v "An error occurred" || echo "  ✓ ECS cluster deleted or already gone"

# 4. Wait for EC2 instance to terminate
if aws ec2 describe-instances --instance-ids i-0e24ffd43ee3ec225 --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null | grep -q "shutting\|terminating"; then
    wait_for_deletion "EC2 Instance" "i-0e24ffd43ee3ec225" \
        "aws ec2 describe-instances --instance-ids i-0e24ffd43ee3ec225 --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null"
fi

# 5. Delete RDS subnet group from Terraform
echo ""
echo "Destroying RDS subnet group from Terraform..."
terraform destroy -target=module.rds.aws_db_subnet_group.this \
    -var-file=terraform.tfvars \
    -var="db_master_password=${TF_VAR_DB_MASTER_PASSWORD:-RohitSajud1234}" \
    -auto-approve 2>&1 | tail -5 || echo "  ✓ Subnet group destroyed or not in state"

# 6. Delete VPCs and all networking resources
echo ""
echo "Deleting VPCs and networking resources..."

for vpc in vpc-0a455c1d1ac94413a vpc-05e5f12d249d1b211; do
    echo ""
    echo "Processing VPC: $vpc"
    
    # Get VPC details
    VPC_EXISTS=$(aws ec2 describe-vpcs --vpc-ids $vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    if [ -z "$VPC_EXISTS" ] || [ "$VPC_EXISTS" == "None" ]; then
        echo "  VPC $vpc doesn't exist, skipping..."
        continue
    fi
    
    # Delete Internet Gateway
    IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
    if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
        echo "  Detaching and deleting Internet Gateway: $IGW"
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $vpc 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW 2>/dev/null || true
    fi
    
    # Delete NAT Gateways
    for nat in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null); do
        if [ -n "$nat" ] && [ "$nat" != "None" ]; then
            echo "  Deleting NAT Gateway: $nat"
            aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>/dev/null || true
            # Wait for NAT gateway to delete
            while aws ec2 describe-nat-gateways --nat-gateway-ids $nat --query 'NatGateways[0].State' --output text 2>/dev/null | grep -q "deleting"; do
                sleep 10
            done
        fi
    done
    
    # Delete Security Groups (except default)
    for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null); do
        if [ -n "$sg" ] && [ "$sg" != "None" ]; then
            echo "  Deleting Security Group: $sg"
            aws ec2 delete-security-group --group-id $sg 2>/dev/null || true
        fi
    done
    
    # Delete Subnets
    for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
        if [ -n "$subnet" ] && [ "$subnet" != "None" ]; then
            echo "  Deleting Subnet: $subnet"
            aws ec2 delete-subnet --subnet-id $subnet 2>/dev/null || true
        fi
    done
    
    # Delete Route Tables (except main)
    for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null); do
        if [ -n "$rt" ] && [ "$rt" != "None" ]; then
            echo "  Deleting Route Table: $rt"
            aws ec2 delete-route-table --route-table-id $rt 2>/dev/null || true
        fi
    done
    
    # Delete VPC
    echo "  Deleting VPC: $vpc"
    aws ec2 delete-vpc --vpc-id $vpc 2>/dev/null || true
    echo "  ✓ VPC $vpc deleted"
done

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "All production resources have been deleted."
echo "You can now run 'terraform apply' to recreate everything fresh."

