# IAM Permissions for RentifyDeployRole

## Overview

The `RentifyDeployRole` used by GitHub Actions needs comprehensive IAM permissions to manage infrastructure via Terraform. This document outlines all required permissions.

## Required Policies

### 1. RDS Permissions
See `policies/rds-deploy-role-policy.json` for RDS-specific permissions.

### 2. IAM and EC2 Permissions
See `policies/deploy-role-iam-ec2-policy.json` for IAM role creation and EC2 instance management.

## Complete Policy Setup

### Option 1: Attach Both Policies (Recommended)

```bash
# Attach RDS policy
aws iam put-role-policy \
  --role-name RentifyDeployRole \
  --policy-name RDSDeployPermissions \
  --policy-document file://policies/rds-deploy-role-policy.json

# Attach IAM/EC2 policy
aws iam put-role-policy \
  --role-name RentifyDeployRole \
  --policy-name IAMEC2DeployPermissions \
  --policy-document file://policies/deploy-role-iam-ec2-policy.json
```

### Option 2: Merge into Single Policy

You can merge both policies into a single policy document for easier management.

## Required Permissions Summary

### IAM Permissions
- `iam:CreateRole` - Create IAM roles (for EC2 instances, ECS tasks, etc.)
- `iam:DeleteRole` - Delete IAM roles
- `iam:GetRole` - Read role details
- `iam:UpdateRole` - Update role configuration
- `iam:AttachRolePolicy` - Attach managed policies to roles
- `iam:DetachRolePolicy` - Detach policies from roles
- `iam:CreateInstanceProfile` - Create instance profiles for EC2
- `iam:AddRoleToInstanceProfile` - Add roles to instance profiles
- `iam:CreatePolicy` - Create custom IAM policies
- `iam:PassRole` - Pass roles to AWS services (EC2, ECS)

### EC2 Permissions
- `ec2:RunInstances` - Launch EC2 instances
- `ec2:TerminateInstances` - Terminate instances
- `ec2:DescribeInstances` - List and describe instances
- `ec2:CreateSecurityGroup` - Create security groups
- `ec2:AuthorizeSecurityGroupIngress` - Add ingress rules
- `ec2:AuthorizeSecurityGroupEgress` - Add egress rules
- `ec2:CreateSecurityGroupRule` - Create security group rules
- `ec2:CreateTags` - Tag resources
- And more EC2 operations for complete infrastructure management

### RDS Permissions
- `rds:CreateDBInstance` - Create RDS instances
- `rds:ModifyDBInstance` - Modify RDS instances
- `rds:CreateDBSubnetGroup` - Create DB subnet groups
- `rds:ModifyDBSubnetGroup` - Modify DB subnet groups
- And more RDS operations

## Resource Restrictions

The IAM policy restricts role creation to resources matching the naming pattern:
- `arn:aws:iam::*:role/rentify-*`
- `arn:aws:iam::*:instance-profile/rentify-*`
- `arn:aws:iam::*:policy/rentify-*`

This ensures the role can only create/modify resources for your project.

## Verification

After attaching the policies, verify permissions:

```bash
# Test IAM role creation (dry run)
aws iam get-role --role-name rentify-dev-test-role 2>&1 || echo "Role doesn't exist (expected)"

# Test EC2 describe (should work)
aws ec2 describe-instances --max-items 1

# Test RDS describe (should work)
aws rds describe-db-instances --max-items 1
```

## Security Best Practices

1. **Least Privilege**: The policies are scoped to specific resource patterns (`rentify-*`)
2. **Resource Restrictions**: IAM operations are limited to your project's naming convention
3. **PassRole Conditions**: `iam:PassRole` includes conditions to only pass roles to specific services
4. **Separate Policies**: Keep policies separate for easier auditing and management

## Troubleshooting

### Error: "not authorized to perform: iam:CreateRole"

**Solution**: Attach the IAM/EC2 policy:
```bash
aws iam put-role-policy \
  --role-name RentifyDeployRole \
  --policy-name IAMEC2DeployPermissions \
  --policy-document file://policies/deploy-role-iam-ec2-policy.json
```

### Error: "not authorized to perform: ec2:RunInstances"

**Solution**: Ensure the EC2 permissions in the IAM/EC2 policy are attached.

### Error: "not authorized to perform: rds:CreateDBInstance"

**Solution**: Attach the RDS policy:
```bash
aws iam put-role-policy \
  --role-name RentifyDeployRole \
  --policy-name RDSDeployPermissions \
  --policy-document file://policies/rds-deploy-role-policy.json
```

## Next Steps

1. Attach both policies to `RentifyDeployRole`
2. Retry your Terraform apply
3. Monitor CloudTrail logs for any additional permission errors

