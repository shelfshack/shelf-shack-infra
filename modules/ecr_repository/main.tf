# ECR Repository Module
# Handles both new and existing repositories gracefully
#
# This module uses an external data source to check if the ECR repository
# already exists before attempting to create it. This prevents the
# "RepositoryAlreadyExistsException" error when the repo was created
# outside of Terraform or in a previous run.

locals {
  tags = merge(var.tags, {
    Module = "ecr"
  })
}

# Check if repository already exists using AWS CLI
# This is safer than a data source because it doesn't fail if repo doesn't exist
data "external" "check_ecr_exists" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    if aws ecr describe-repositories --repository-names "${var.name}" --region "${var.aws_region}" >/dev/null 2>&1; then
      REPO_URL=$(aws ecr describe-repositories --repository-names "${var.name}" --region "${var.aws_region}" --query 'repositories[0].repositoryUri' --output text 2>/dev/null)
      REPO_ARN=$(aws ecr describe-repositories --repository-names "${var.name}" --region "${var.aws_region}" --query 'repositories[0].repositoryArn' --output text 2>/dev/null)
      echo "{\"exists\": \"true\", \"repository_url\": \"$REPO_URL\", \"repository_arn\": \"$REPO_ARN\"}"
    else
      echo "{\"exists\": \"false\", \"repository_url\": \"\", \"repository_arn\": \"\"}"
    fi
  EOT
  ]
}

# Determine if we need to create the repository
locals {
  repository_exists = var.create_if_not_exists ? (
    try(data.external.check_ecr_exists[0].result.exists, "false") == "true"
  ) : false
  
  should_create = !local.repository_exists
}

# Create repository only if it doesn't exist
resource "aws_ecr_repository" "this" {
  count                = local.should_create ? 1 : 0
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  # Force delete allows destroying even with images present
  force_delete = var.force_delete
}

# Lifecycle policy (only if we created the repo)
resource "aws_ecr_lifecycle_policy" "this" {
  count      = local.should_create && var.lifecycle_policy != null ? 1 : 0
  repository = aws_ecr_repository.this[0].name
  policy     = var.lifecycle_policy
}

# Local values to normalize outputs regardless of create vs existing
locals {
  repository_name = var.name
  
  repository_url = local.should_create ? (
    length(aws_ecr_repository.this) > 0 ? aws_ecr_repository.this[0].repository_url : ""
  ) : (
    try(data.external.check_ecr_exists[0].result.repository_url, "")
  )
  
  repository_arn = local.should_create ? (
    length(aws_ecr_repository.this) > 0 ? aws_ecr_repository.this[0].arn : ""
  ) : (
    try(data.external.check_ecr_exists[0].result.repository_arn, "")
  )
}
