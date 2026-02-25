# S3 Bucket Module for Application Uploads
# Creates an S3 bucket with proper configuration for file uploads

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  tags = merge(var.tags, {
    Module = "s3-uploads"
  })
}

# S3 Bucket
resource "aws_s3_bucket" "uploads" {
  bucket = var.bucket_name

  tags = merge(local.tags, {
    Name = var.bucket_name
  })
}

# Empty bucket before destruction - runs automatically during destroy
# This ensures the bucket can be deleted even if it contains objects
resource "null_resource" "empty_bucket" {
  triggers = {
    bucket_name = aws_s3_bucket.uploads.id
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      BUCKET="${self.triggers.bucket_name}"
      echo "Emptying S3 bucket: $BUCKET"
      
      # Delete all objects (non-versioned)
      aws s3 rm s3://$BUCKET --recursive 2>/dev/null || echo "No objects to delete or bucket doesn't exist"
      
      # Delete all object versions (if versioning was enabled)
      # Use a simpler approach that doesn't require jq
      aws s3api list-object-versions --bucket $BUCKET --output json 2>/dev/null | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for version in data.get('Versions', []):
        key = version.get('Key', '')
        vid = version.get('VersionId', '')
        if key and vid:
            print(f'{key}|{vid}')
except:
    pass
" 2>/dev/null | while IFS='|' read -r key version; do
        [ -n "$key" ] && [ -n "$version" ] && \
        aws s3api delete-object --bucket $BUCKET --key "$key" --version-id "$version" 2>/dev/null || true
      done
      
      # Delete all delete markers
      aws s3api list-object-versions --bucket $BUCKET --output json 2>/dev/null | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for marker in data.get('DeleteMarkers', []):
        key = marker.get('Key', '')
        vid = marker.get('VersionId', '')
        if key and vid:
            print(f'{key}|{vid}')
except:
    pass
" 2>/dev/null | while IFS='|' read -r key version; do
        [ -n "$key" ] && [ -n "$version" ] && \
        aws s3api delete-object --bucket $BUCKET --key "$key" --version-id "$version" 2>/dev/null || true
      done
      
      echo "Bucket emptied successfully"
    EOT
  }
}

# Enable versioning (optional but recommended)
resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (we'll use bucket policy for specific public access)
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy for public read access to specific prefixes and ECS task role uploads
locals {
  # Base statements for public read access
  base_statements = [
    {
      Sid    = "AllowPublicReadItem"
      Effect = "Allow"
      Principal = "*"
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::${var.bucket_name}/${var.item_prefix}/*"
    },
    {
      Sid    = "AllowPublicReadProfile"
      Effect = "Allow"
      Principal = "*"
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::${var.bucket_name}/${var.profile_prefix}/*"
    }
  ]
  
  # ECS task role statements (if provided) - use flatten to handle conditional list
  ecs_statements = flatten([
    for arn in var.ecs_task_role_arn != null ? [var.ecs_task_role_arn] : [] : [
      {
        Sid    = "AllowECSTaskUpload"
        Effect = "Allow"
        Principal = {
          AWS = arn
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
      {
        Sid    = "AllowECSTaskList"
        Effect = "Allow"
        Principal = {
          AWS = arn
        }
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.bucket_name}"
      }
    ]
  ])
  
  # Combine all statements
  bucket_policy_statements = concat(local.base_statements, local.ecs_statements)
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.bucket_policy_statements
  })

  depends_on = [
    aws_s3_bucket_public_access_block.uploads,
    null_resource.empty_bucket
  ]
}

# CORS configuration for web uploads
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Lifecycle configuration (optional - to manage old versions)
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  count  = var.enable_versioning && var.lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_days
    }
  }
}
