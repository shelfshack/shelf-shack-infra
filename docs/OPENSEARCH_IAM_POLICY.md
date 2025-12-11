# IAM Policy for ECS Task Role - OpenSearch Access

This document provides the IAM policy and Terraform configuration to grant your ECS task role access to the OpenSearch domain.

## IAM Policy JSON

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpGet",
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpDelete"
      ],
      "Resource": "arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"
    },
    {
      "Effect": "Deny",
      "Action": [
        "es:*"
      ],
      "NotResource": "arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"
    }
  ]
}
```

## Policy Explanation

- **Allow Statement**: Grants the ECS task role permission to perform the four essential OpenSearch HTTP operations (GET, POST, PUT, DELETE) on the `shelfshack-search` domain and all its resources (`/*`).

- **Deny Statement**: Explicitly denies access to any OpenSearch domain that is NOT `shelfshack-search`. This ensures the task role cannot access other OpenSearch domains in your account.

## Terraform Implementation

The policy has been integrated into the ECS service module. The module automatically creates an inline policy on the task role when `opensearch_domain_arn` is provided.

### Already Configured

The policy is already configured in:
- `modules/ecs_service/main.tf` - Creates the inline policy
- `modules/ecs_service/variables.tf` - Adds `opensearch_domain_arn` variable
- `envs/dev/main.tf` - Passes the OpenSearch domain ARN to the ECS module

### Manual Configuration (Alternative)

If you prefer to add this manually or outside the module, you can use:

```hcl
# In envs/dev/main.tf or wherever you manage the task role

data "aws_iam_policy_document" "opensearch_access" {
  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut",
      "es:ESHttpDelete"
    ]
    resources = ["arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"]
  }

  statement {
    effect = "Deny"
    actions = ["es:*"]
    not_resources = ["arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_opensearch" {
  name   = "${local.name}-task-opensearch-access"
  role   = module.ecs_service.task_role_arn
  policy = data.aws_iam_policy_document.opensearch_access.json
}
```

## AWS CLI Alternative

If you prefer to attach the policy using AWS CLI:

```bash
# Save the policy JSON to a file
cat > opensearch-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpGet",
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpDelete"
      ],
      "Resource": "arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"
    },
    {
      "Effect": "Deny",
      "Action": ["es:*"],
      "NotResource": "arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"
    }
  ]
}
EOF

# Attach as inline policy to the task role
aws iam put-role-policy \
  --role-name rentify-dev-task-role \
  --policy-name opensearch-access \
  --policy-document file://opensearch-policy.json
```

Replace `rentify-dev-task-role` with your actual task role name.

## Verification

After applying the Terraform changes, verify the policy is attached:

```bash
# List inline policies on the task role
aws iam list-role-policies --role-name rentify-dev-task-role

# Get the policy document
aws iam get-role-policy \
  --role-name rentify-dev-task-role \
  --policy-name rentify-dev-task-opensearch-access
```

## Security Notes

1. **Least Privilege**: The policy only grants the minimum required OpenSearch operations (HTTP methods).

2. **Explicit Deny**: The deny statement ensures that even if other policies grant broader access, this role cannot access other OpenSearch domains.

3. **Resource-Specific**: The allow statement is scoped to a specific domain ARN, not a wildcard.

4. **Inline Policy**: Using an inline policy keeps the permissions tightly coupled with the role and makes it easier to manage in Terraform.






