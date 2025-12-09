locals {
  tags = merge(var.tags, {
    Module = "ecr"
  })
}

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(local.tags, {
    Name = var.name
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.lifecycle_policy == null ? 0 : 1
  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy
}
