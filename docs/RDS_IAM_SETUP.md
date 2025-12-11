# RDS IAM Permissions Setup

## Problem

When deploying RDS resources via Terraform using the `RentifyDeployRole` (or similar GitHub Actions deployment role), you may encounter the following error:

```
Error: updating RDS DB Subnet Group (...): operation error RDS: ModifyDBSubnetGroup, 
https response error StatusCode: 403, RequestID: ..., api error AccessDenied: 
User: arn:aws:sts::ACCOUNT:assumed-role/RentifyDeployRole/GitHubActions is not authorized 
to perform: rds:ModifyDBSubnetGroup on resource: arn:aws:rds:REGION:ACCOUNT:subgrp:...
```

This error occurs because the IAM role lacks the necessary RDS permissions to manage DB subnet groups and other RDS resources.

## Solution

Attach the RDS permissions policy to your deployment role. A complete policy document is provided in `policies/rds-deploy-role-policy.json`.

### Option 1: Attach Policy via AWS Console

1. Navigate to IAM → Roles → `RentifyDeployRole`
2. Click "Add permissions" → "Create inline policy" or "Attach policies"
3. Use the JSON editor and paste the contents of `policies/rds-deploy-role-policy.json`
4. Review and save the policy

### Option 2: Attach Policy via AWS CLI

```bash
# Create the policy
aws iam put-role-policy \
  --role-name RentifyDeployRole \
  --policy-name RDSDeployPermissions \
  --policy-document file://policies/rds-deploy-role-policy.json
```

### Option 3: Attach Policy via Terraform (if managing the role in Terraform)

If you manage the `RentifyDeployRole` in Terraform, you can attach the policy like this:

```hcl
data "aws_iam_policy_document" "rds_deploy" {
  source_json = file("${path.module}/policies/rds-deploy-role-policy.json")
}

resource "aws_iam_role_policy" "rds_deploy" {
  name   = "RDSDeployPermissions"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.rds_deploy.json
}
```

## Required RDS Permissions

The policy includes the following RDS actions:

- `rds:AddTagsToResource` - Add tags to RDS resources
- `rds:CreateDBInstance` - Create RDS database instances
- `rds:CreateDBSubnetGroup` - Create DB subnet groups
- `rds:DeleteDBInstance` - Delete RDS database instances
- `rds:DeleteDBSubnetGroup` - Delete DB subnet groups
- `rds:DescribeDBInstances` - Describe RDS instances
- `rds:DescribeDBSubnetGroups` - Describe DB subnet groups
- `rds:ListTagsForResource` - List tags on RDS resources
- `rds:ModifyDBInstance` - Modify RDS instances
- `rds:ModifyDBSubnetGroup` - **Required for updating subnet groups** (this was missing)
- `rds:RemoveTagsFromResource` - Remove tags from RDS resources

Additionally, the policy includes EC2 permissions needed for RDS operations:

- `ec2:CreateNetworkInterface` - Create network interfaces for RDS
- `ec2:DeleteNetworkInterface` - Delete network interfaces
- `ec2:DescribeNetworkInterfaces` - Describe network interfaces
- `ec2:DescribeSecurityGroups` - Describe security groups
- `ec2:DescribeSubnets` - Describe subnets
- `ec2:DescribeVpcs` - Describe VPCs

## Verification

After attaching the policy, verify the permissions by running:

```bash
# Test if the role can describe DB subnet groups
aws rds describe-db-subnet-groups --region us-east-1

# Or test with the assumed role
aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/RentifyDeployRole --role-session-name test
```

Then retry your Terraform apply operation.

## Security Considerations

The policy uses `Resource: "*"` for simplicity. For production environments, consider restricting resources to specific ARNs:

```json
{
  "Effect": "Allow",
  "Action": [
    "rds:ModifyDBSubnetGroup"
  ],
  "Resource": [
    "arn:aws:rds:REGION:ACCOUNT:subgrp:*-db-subnets"
  ]
}
```

This limits the policy to only affect DB subnet groups matching your naming convention.

