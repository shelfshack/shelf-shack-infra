#!/usr/bin/env bash
# Force-delete a VPC and all dependencies via AWS CLI when Terraform destroy gets stuck.
# Run from repo root. After this, run: cd envs/<env> && terraform state rm module.networking && terraform destroy -refresh=false -var-file=terraform.tfvars -auto-approve
#
# Usage: ./scripts/force-destroy-vpc.sh [dev|prod] [vpc-id]
#   If vpc-id is omitted, it is read from Terraform state for the env.

set -e

ENVIRONMENT="${1:-}"
VPC_ID="${2:-}"
REGION="${AWS_REGION:-us-east-1}"

if [ -z "$ENVIRONMENT" ] || { [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; }; then
    echo "Usage: $0 <dev|prod> [vpc-id]"
    echo "  Example: $0 prod vpc-075d5a396f1b55bd8"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$REPO_ROOT/envs/$ENVIRONMENT"
cd "$ENV_DIR" || exit 1

if [ -z "$VPC_ID" ]; then
    echo "Getting VPC ID from Terraform state..."
    VPC_ID=$(terraform state show 'module.networking.aws_vpc.this[0]' 2>/dev/null | grep '^id ' | sed 's/^id *= *"\(.*\)"/\1/' || true)
fi
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "null" ]; then
    echo "Error: Could not get VPC ID. Pass it as second argument: $0 $ENVIRONMENT vpc-xxxx"
    exit 1
fi

if [ -f "terraform.tfvars" ]; then
    REGION=$(grep -E '^\s*aws_region\s*=' terraform.tfvars 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | tr -d ' ') || true
fi
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

echo "========================================="
echo "Force-deleting VPC and dependencies"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "VPC ID:      $VPC_ID"
echo "Region:      $REGION"
echo "========================================="

# 1) Delete NAT gateways (takes 2-5 min; must be done first)
echo "Checking for NAT gateways..."
NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" --region "$REGION" --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || true)
if [ -n "$NAT_IDS" ]; then
    for NID in $NAT_IDS; do
        echo "Deleting NAT gateway $NID..."
        aws ec2 delete-nat-gateway --nat-gateway-id "$NID" --region "$REGION" --output text
    done
    echo "Waiting for NAT gateway(s) to be deleted (up to 5 min)..."
    for i in {1..30}; do
        REMAIN=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending,deleting" --region "$REGION" --query 'length(NatGateways)' --output text 2>/dev/null || echo "0")
        if [ "$REMAIN" = "0" ]; then break; fi
        echo "  Waiting... (${i}0s)"
        sleep 10
    done
    # Release EIPs that were attached to NAT
    EIP_ALLOCS=$(aws ec2 describe-addresses --region "$REGION" --filters "Name=domain,Values=vpc" --query "Addresses[?NetworkInterfaceId==null].AllocationId" --output text 2>/dev/null || true)
    for AID in $EIP_ALLOCS; do
        aws ec2 describe-addresses --allocation-ids "$AID" --region "$REGION" --query 'Addresses[0].Tags' --output text 2>/dev/null | grep -q "terraform" && \
        aws ec2 release-address --allocation-id "$AID" --region "$REGION" 2>/dev/null || true
    done
fi

# 2) Delete VPC endpoints
echo "Deleting VPC endpoints..."
EP_IDS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null || true)
for EP in $EP_IDS; do
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$EP" --region "$REGION" 2>/dev/null || true
done

# 3) Detach and delete Internet gateway
echo "Detaching and deleting Internet gateway..."
IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$REGION" --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null || true)
for IGW in $IGW_IDS; do
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION" 2>/dev/null || true
done

# 4) Delete network interfaces (e.g. leftover from ECS/Lambda)
echo "Deleting network interfaces..."
ENI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'NetworkInterfaces[*].[NetworkInterfaceId,Attachment.AttachmentId]' --output text 2>/dev/null || true)
echo "$ENI_IDS" | while read -r eni att; do
    [ -z "$eni" ] && continue
    if [ -n "$att" ] && [ "$att" != "None" ]; then
        aws ec2 detach-network-interface --attachment-id "$att" --region "$REGION" --force 2>/dev/null || true
        sleep 2
    fi
    aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>/dev/null || true
done

# 5) Delete subnets
echo "Deleting subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'Subnets[*].SubnetId' --output text 2>/dev/null || true)
for SID in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id "$SID" --region "$REGION" 2>/dev/null || true
done

# 6) Delete route table associations and custom route tables
echo "Deleting route tables..."
RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'RouteTables[?length(Associations[?Main==`true`])==`0`].RouteTableId' --output text 2>/dev/null || true)
for RT in $RT_IDS; do
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$RT" --region "$REGION" --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text 2>/dev/null || true)
    for A in $ASSOC_IDS; do
        aws ec2 disassociate-route-table --association-id "$A" --region "$REGION" 2>/dev/null || true
    done
    aws ec2 delete-route-table --route-table-id "$RT" --region "$REGION" 2>/dev/null || true
done

# 7) Delete security groups (except default)
echo "Deleting security groups..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
for SG in $SG_IDS; do
    aws ec2 delete-security-group --group-id "$SG" --region "$REGION" 2>/dev/null || true
done

# 8) Delete VPC (retry once after short wait in case SGs still releasing)
echo "Deleting VPC $VPC_ID..."
if ! aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null; then
    echo "First attempt failed. Waiting 15s and retrying..."
    sleep 15
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" && echo "VPC deleted." || echo "VPC delete failed (check for remaining ENIs/SGs in console)."
else
    echo "VPC deleted."
fi

echo ""
echo "========================================="
echo "Next: remove networking from state and re-run destroy"
echo "========================================="
echo "  cd $ENV_DIR"
echo "  terraform state rm 'module.networking'"
echo "  terraform destroy -refresh=false -var-file=terraform.tfvars -auto-approve"
echo ""
