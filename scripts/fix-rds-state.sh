#!/bin/bash
#
# Fix RDS Terraform state - Import existing RDS resources
# This prevents Terraform from trying to delete them
#

set -e

ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "========================================="
echo "Fixing RDS Terraform State: $ENVIRONMENT"
echo "========================================="
echo ""

# Change to environment directory
cd "$(dirname "$0")/../envs/$ENVIRONMENT"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

echo "Step 1: Check what RDS resources exist in AWS"
echo "----------------------------------------------"

# Check for RDS instance
RDS_INSTANCE_ID="shelfshack-${ENVIRONMENT}-postgres"
echo "Checking for RDS instance: $RDS_INSTANCE_ID"

RDS_EXISTS=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "")

if [ -n "$RDS_EXISTS" ] && [ "$RDS_EXISTS" != "None" ]; then
    echo "✅ RDS instance exists: $RDS_EXISTS"

    # Check if it's in Terraform state
    if terraform state list | grep -q "module.rds.aws_db_instance.this"; then
        echo "  Already in Terraform state"
    else
        echo "  Not in Terraform state - importing..."
        terraform import 'module.rds.aws_db_instance.this[0]' "$RDS_INSTANCE_ID" || echo "  Import failed"
    fi
else
    echo "❌ RDS instance does not exist"
fi

echo ""
echo "Step 2: Check subnet group"
echo "---------------------------"

SUBNET_GROUP_NAME="shelfshack-${ENVIRONMENT}-db-subnets"
echo "Checking for subnet group: $SUBNET_GROUP_NAME"

SG_EXISTS=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --region "$AWS_REGION" \
    --query 'DBSubnetGroups[0].DBSubnetGroupName' \
    --output text 2>/dev/null || echo "")

if [ -n "$SG_EXISTS" ] && [ "$SG_EXISTS" != "None" ]; then
    echo "✅ Subnet group exists: $SG_EXISTS"

    # Check if it's in Terraform state
    if terraform state list | grep -q "module.rds.aws_db_subnet_group.this"; then
        echo "  Already in Terraform state"
    else
        echo "  Not in Terraform state - importing..."
        terraform import 'module.rds.aws_db_subnet_group.this[0]' "$SUBNET_GROUP_NAME" || echo "  Import failed"
    fi
else
    echo "❌ Subnet group does not exist"
fi

echo ""
echo "Step 3: Check security group"
echo "-----------------------------"

SG_NAME="shelfshack-${ENVIRONMENT}-db-sg"
echo "Checking for security group: $SG_NAME"

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=shelfshack-${ENVIRONMENT}-vpc" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$SG_NAME" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        echo "✅ Security group exists: $SG_ID"

        # Check if it's in Terraform state
        if terraform state list | grep -q "module.rds.aws_security_group.this"; then
            echo "  Already in Terraform state"
        else
            echo "  Not in Terraform state - importing..."
            terraform import 'module.rds.aws_security_group.this[0]' "$SG_ID" || echo "  Import failed"
        fi
    else
        echo "❌ Security group does not exist"
    fi
fi

echo ""
echo "Step 4: Update DATABASE_URL in Secrets Manager"
echo "-----------------------------------------------"

if [ -n "$RDS_EXISTS" ]; then
    ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)

    echo "RDS Endpoint: $ENDPOINT"
    echo ""
    echo "Current DATABASE_URL in Secrets Manager:"

    CURRENT_URL=$(aws secretsmanager get-secret-value \
        --secret-id "dev/shelfshack/backend_secrets" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('DATABASE_URL', 'NOT SET'))" 2>/dev/null || echo "ERROR")

    echo "  $CURRENT_URL"

    # Check if DATABASE_URL needs updating
    if [[ "$CURRENT_URL" != *"$ENDPOINT"* ]]; then
        echo ""
        echo "⚠️  DATABASE_URL needs to be updated!"
        echo "Expected endpoint: $ENDPOINT"
        echo ""
        echo "Run this command to update:"
        echo ""
        echo "  # Get current secrets"
        echo "  aws secretsmanager get-secret-value \\"
        echo "    --secret-id dev/shelfshack/backend_secrets \\"
        echo "    --region us-east-1 \\"
        echo "    --query SecretString \\"
        echo "    --output text > /tmp/secrets.json"
        echo ""
        echo "  # Update DATABASE_URL (use python or jq)"
        echo "  python3 -c \"import json; d = json.load(open('/tmp/secrets.json')); d['DATABASE_URL'] = 'postgresql://dbadmin_shelfshack:RohitSajud1234@${ENDPOINT}:5432/shelfshack'; json.dump(d, open('/tmp/secrets.json', 'w'))\""
        echo ""
        echo "  # Update the secret"
        echo "  aws secretsmanager update-secret \\"
        echo "    --secret-id dev/shelfshack/backend_secrets \\"
        echo "    --secret-string file:///tmp/secrets.json \\"
        echo "    --region us-east-1"
    else
        echo "✅ DATABASE_URL is correct"
    fi
fi

echo ""
echo "========================================="
echo "✅ RDS State Fix Complete!"
echo "========================================="
echo ""
echo "Next: Run 'terraform plan' to verify no resources will be destroyed"
echo ""
