# IAM Policy for ECS Task Role to Access OpenSearch Domain
# 
# This policy grants the ECS task role permission to perform OpenSearch operations
# on the shelfshack-search domain only, and explicitly denies access to any other
# OpenSearch domains.

# Option 1: Add as inline policy to the existing task role in the ECS service module
# Add this to modules/ecs_service/main.tf after the task role is created:

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

resource "aws_iam_role_policy" "task_opensearch" {
  name   = "${var.name}-task-opensearch-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.opensearch_access.json
}

# Option 2: If you want to add this directly in envs/dev/main.tf:
# (Uncomment and adjust the resource name/ARNs as needed)

# data "aws_iam_policy_document" "opensearch_access" {
#   statement {
#     effect = "Allow"
#     actions = [
#       "es:ESHttpGet",
#       "es:ESHttpPost",
#       "es:ESHttpPut",
#       "es:ESHttpDelete"
#     ]
#     resources = ["arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"]
#   }
#
#   statement {
#     effect = "Deny"
#     actions = ["es:*"]
#     not_resources = ["arn:aws:es:us-east-1:506852294788:domain/shelfshack-search/*"]
#   }
# }
#
# resource "aws_iam_role_policy" "ecs_task_opensearch" {
#   name   = "${local.name}-task-opensearch-access"
#   role   = module.ecs_service.task_role_arn
#   policy = data.aws_iam_policy_document.opensearch_access.json
# }






