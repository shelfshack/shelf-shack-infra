#!/bin/bash
# Pre-Apply Cleanup Script for Terraform
# This script ensures a clean state before terraform apply by checking for
# existing resources that might conflict with Terraform's creation.
#
# Usage: ./scripts/pre-apply-cleanup.sh <environment>
# Example: ./scripts/pre-apply-cleanup.sh prod

set -e

ENV="${1:-dev}"
REGION="${AWS_REGION:-us-east-1}"
NAME_PREFIX="shelfshack-${ENV}"

echo "=============================================="
echo "Pre-Apply Cleanup for: ${ENV}"
echo "Region: ${REGION}"
echo "Name prefix: ${NAME_PREFIX}"
echo "=============================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cleanup_count=0

# Function to check and optionally delete a resource
check_and_report() {
    local resource_type="$1"
    local resource_name="$2"
    local exists="$3"
    
    if [ "$exists" = "true" ]; then
        echo -e "${YELLOW}⚠ Found existing: ${resource_type} - ${resource_name}${NC}"
        ((cleanup_count++))
        return 0
    fi
    return 1
}

echo "Checking for existing resources..."
echo ""

# ============================================================================
# IAM ROLES
# ============================================================================
echo "→ Checking IAM Roles..."
for role in "${NAME_PREFIX}-execution-role" "${NAME_PREFIX}-task-role" "${NAME_PREFIX}-websocket-lambda-role" "${NAME_PREFIX}-opensearch-ec2-role" "shelfshackDeployRole-${ENV}"; do
    if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
        check_and_report "IAM Role" "$role" "true"
        if [ "${CLEANUP:-false}" = "true" ]; then
            echo "   Cleaning up $role..."
            # Detach policies
            for policy in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
            done
            # Delete inline policies
            for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[*]' --output text 2>/dev/null); do
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
            done
            # Remove from instance profiles
            for profile in $(aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null); do
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role" 2>/dev/null || true
            done
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || true
            echo -e "   ${GREEN}✓ Deleted${NC}"
        fi
    fi
done

# ============================================================================
# IAM INSTANCE PROFILES
# ============================================================================
echo "→ Checking IAM Instance Profiles..."
for profile in "${NAME_PREFIX}-opensearch-ec2-profile"; do
    if aws iam get-instance-profile --instance-profile-name "$profile" >/dev/null 2>&1; then
        check_and_report "IAM Instance Profile" "$profile" "true"
        if [ "${CLEANUP:-false}" = "true" ]; then
            aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
            echo -e "   ${GREEN}✓ Deleted${NC}"
        fi
    fi
done

# ============================================================================
# IAM POLICIES
# ============================================================================
echo "→ Checking IAM Policies..."
for policy_name in "${NAME_PREFIX}-execution-secrets"; do
    POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${policy_name}'].Arn" --output text 2>/dev/null)
    if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
        check_and_report "IAM Policy" "$policy_name" "true"
        if [ "${CLEANUP:-false}" = "true" ]; then
            aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
            echo -e "   ${GREEN}✓ Deleted${NC}"
        fi
    fi
done

# ============================================================================
# RDS SUBNET GROUPS
# ============================================================================
echo "→ Checking RDS Subnet Groups..."
if aws rds describe-db-subnet-groups --db-subnet-group-name "${NAME_PREFIX}-db-subnets" >/dev/null 2>&1; then
    check_and_report "RDS Subnet Group" "${NAME_PREFIX}-db-subnets" "true"
    if [ "${CLEANUP:-false}" = "true" ]; then
        aws rds delete-db-subnet-group --db-subnet-group-name "${NAME_PREFIX}-db-subnets" 2>/dev/null || echo "   (in use by RDS instance)"
    fi
fi

# ============================================================================
# DYNAMODB TABLES
# ============================================================================
echo "→ Checking DynamoDB Tables..."
if aws dynamodb describe-table --table-name "${NAME_PREFIX}-websocket-connections" --region "$REGION" >/dev/null 2>&1; then
    check_and_report "DynamoDB Table" "${NAME_PREFIX}-websocket-connections" "true"
    if [ "${CLEANUP:-false}" = "true" ]; then
        aws dynamodb delete-table --table-name "${NAME_PREFIX}-websocket-connections" --region "$REGION" 2>/dev/null || true
        echo -e "   ${GREEN}✓ Deletion initiated${NC}"
    fi
fi

# ============================================================================
# SECURITY GROUPS
# ============================================================================
echo "→ Checking Security Groups..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" --query 'Vpcs[0].VpcId' --output text --region "$REGION" 2>/dev/null)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    for sg_name in "${NAME_PREFIX}-db-sg" "${NAME_PREFIX}-opensearch-ec2-sg" "${NAME_PREFIX}-svc-sg" "${NAME_PREFIX}-alb-sg" "${NAME_PREFIX}-ssm-endpoints"; do
        SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$sg_name" --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null)
        if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
            check_and_report "Security Group" "$sg_name ($SG_ID)" "true"
            if [ "${CLEANUP:-false}" = "true" ]; then
                aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" 2>/dev/null || echo "   (has dependencies)"
            fi
        fi
    done
fi

# ============================================================================
# ECS CLUSTERS
# ============================================================================
echo "→ Checking ECS Clusters..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${NAME_PREFIX}-cluster" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    check_and_report "ECS Cluster" "${NAME_PREFIX}-cluster" "true"
    if [ "${CLEANUP:-false}" = "true" ]; then
        # Delete services first
        for svc in $(aws ecs list-services --cluster "${NAME_PREFIX}-cluster" --region "$REGION" --query 'serviceArns[*]' --output text 2>/dev/null); do
            aws ecs update-service --cluster "${NAME_PREFIX}-cluster" --service "$svc" --desired-count 0 --region "$REGION" 2>/dev/null || true
            aws ecs delete-service --cluster "${NAME_PREFIX}-cluster" --service "$svc" --force --region "$REGION" 2>/dev/null || true
        done
        sleep 5
        aws ecs delete-cluster --cluster "${NAME_PREFIX}-cluster" --region "$REGION" 2>/dev/null || true
        echo -e "   ${GREEN}✓ Deleted${NC}"
    fi
fi

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================
echo "→ Checking CloudWatch Log Groups..."
for log_group in "/ecs/${NAME_PREFIX}" "/aws/ecs/executioncommand/${NAME_PREFIX}-cluster" "/aws/ecs/containerinsights/${NAME_PREFIX}-cluster/performance"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
        check_and_report "CloudWatch Log Group" "$log_group" "true"
        if [ "${CLEANUP:-false}" = "true" ]; then
            aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
            echo -e "   ${GREEN}✓ Deleted${NC}"
        fi
    fi
done

# ============================================================================
# LAMBDA FUNCTIONS
# ============================================================================
echo "→ Checking Lambda Functions..."
if aws lambda get-function --function-name "${NAME_PREFIX}-websocket-proxy" --region "$REGION" >/dev/null 2>&1; then
    check_and_report "Lambda Function" "${NAME_PREFIX}-websocket-proxy" "true"
    if [ "${CLEANUP:-false}" = "true" ]; then
        aws lambda delete-function --function-name "${NAME_PREFIX}-websocket-proxy" --region "$REGION" 2>/dev/null || true
        echo -e "   ${GREEN}✓ Deleted${NC}"
    fi
fi

# ============================================================================
# API GATEWAYS
# ============================================================================
echo "→ Checking API Gateways..."
for api_id in $(aws apigatewayv2 get-apis --region "$REGION" --query "Items[?contains(Name, '${NAME_PREFIX}')].ApiId" --output text 2>/dev/null); do
    API_NAME=$(aws apigatewayv2 get-api --api-id "$api_id" --region "$REGION" --query 'Name' --output text 2>/dev/null)
    check_and_report "API Gateway" "$API_NAME ($api_id)" "true"
    if [ "${CLEANUP:-false}" = "true" ]; then
        aws apigatewayv2 delete-api --api-id "$api_id" --region "$REGION" 2>/dev/null || true
        echo -e "   ${GREEN}✓ Deleted${NC}"
    fi
done

echo ""
echo "=============================================="
if [ $cleanup_count -gt 0 ]; then
    if [ "${CLEANUP:-false}" = "true" ]; then
        echo -e "${GREEN}✓ Cleanup complete! $cleanup_count resources processed.${NC}"
    else
        echo -e "${YELLOW}⚠ Found $cleanup_count existing resources that may conflict.${NC}"
        echo ""
        echo "To clean up these resources, run:"
        echo -e "  ${GREEN}CLEANUP=true ./scripts/pre-apply-cleanup.sh ${ENV}${NC}"
        echo ""
        echo "Or import them into Terraform state with:"
        echo "  terraform import <resource_address> <resource_id>"
    fi
else
    echo -e "${GREEN}✓ No conflicting resources found. Safe to run terraform apply.${NC}"
fi
echo "=============================================="

