# Manual vs Terraform: Migration from "rentify" to "shelfshack"

This document clarifies what you need to handle **manually** vs what **Terraform will automatically create** when migrating from `rentify-dev` to `shelfshack-dev` naming.

## ⚠️ Critical: Must Do BEFORE `terraform apply`

These resources **MUST exist** before Terraform can initialize or run:

### 1. Terraform State Backend (S3 + DynamoDB)
**Status:** ❌ **MANUAL - Must create first**

**Resources:**
- S3 Bucket: `shelfshack-terraform-state`
- DynamoDB Table: `shelfshack-terraform-locks`

**Why Manual:** Terraform needs these to store state. They must exist before `terraform init`.

**Commands:**
```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket shelfshack-terraform-state \
  --region us-east-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket shelfshack-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket shelfshack-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name shelfshack-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Application S3 Bucket (Uploads)
**Status:** ❌ **MANUAL - Must create before ECS service starts**

**Resource:**
- S3 Bucket: `shelfshack-dev-uploads`

**Why Manual:** Referenced in `app_environment.S3_BUCKET_NAME` but not created by Terraform.

**Command:**
```bash
aws s3api create-bucket \
  --bucket shelfshack-dev-uploads \
  --region us-east-1

# IMPORTANT: Copy bucket configurations from old bucket
# 1. Configure public access block (must be done BEFORE bucket policy)
aws s3api put-public-access-block \
  --bucket shelfshack-dev-uploads \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# 2. Apply bucket policy (allows public read/write for specific paths)
aws s3api put-bucket-policy \
  --bucket shelfshack-dev-uploads \
  --policy file://policies/s3-bucket-policy.json

# 3. Configure encryption
aws s3api put-bucket-encryption \
  --bucket shelfshack-dev-uploads \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'

# 4. Configure CORS if needed for web uploads
# Option 1: Using the cors-config.json file (created in repo root)
aws s3api put-bucket-cors \
  --bucket shelfshack-dev-uploads \
  --cors-configuration file://cors-config.json

# Option 2: Inline CORS configuration (customize as needed)
aws s3api put-bucket-cors \
  --bucket shelfshack-dev-uploads \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }]
  }'
```

**Note:** The `s3-bucket-policy.json` file is located at `policies/s3-bucket-policy.json` with the correct bucket name (`shelfshack-dev-uploads`). It includes:
- Public read access to `item_images/*` and `profile_photos/*`
- Public write access (PutObject) to the entire bucket

### 3. Secrets Manager Secrets
**Status:** ❌ **MANUAL - Must create or migrate**

**Resources:**
- Secret: `shelfshack/db_url` (or `shelfshack/dev/db-url`)
- Any other secrets referenced in `app_secrets`

**Why Manual:** Terraform references existing secrets but doesn't create them.

**Options:**
- **Option A:** Create new secrets with new names
- **Option B:** Keep old secret names and update Terraform to reference them
- **Option C:** Copy/rename secrets from `rentify/...` to `shelfshack/...`

**Command (Option A - Create New):**
```bash
aws secretsmanager create-secret \
  --name shelfshack/dev/db-url \
  --secret-string '{"DATABASE_URL":"postgresql://..."}'
```

**Command (Option C - Copy from Old):**
```bash
# Get old secret value
OLD_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id rentify/db_url \
  --query SecretString --output text)

# Create new secret
aws secretsmanager create-secret \
  --name shelfshack/db_url \
  --secret-string "$OLD_SECRET"
```

---

## ✅ Automatic: Terraform Will Create These

When you run `terraform apply`, Terraform will automatically create:

### 1. ECR Repository
- ✅ `shelfshack-dev-repo`
- **Action:** Terraform creates it via `module.ecr`

### 2. IAM Roles
- ✅ `shelfshack-dev-execution-role` (ECS task execution)
- ✅ `shelfshack-dev-task-role` (ECS task role)
- ✅ `shelfshack-dev-websocket-lambda-role` (Lambda execution)
- **Action:** Terraform creates these via `module.ecs_service` and `module.websocket_lambda`

### 3. IAM Policies
- ✅ `shelfshack-dev-execution-secrets` (Secrets Manager access)
- ✅ `shelfshack-dev-task-s3` (S3 access)
- ✅ `shelfshack-dev-lambda-dynamodb-policy` (DynamoDB access)
- ✅ `shelfshack-dev-lambda-apigw-policy` (API Gateway access)
- **Action:** Terraform creates these as inline policies on the roles

### 4. DynamoDB Tables
- ✅ `shelfshack-dev-websocket-connections` (WebSocket connections)
- **Note:** `shelfshack-terraform-locks` is manual (see above)
- **Action:** Terraform creates via `module.websocket_lambda`

### 5. Lambda Functions
- ✅ `shelfshack-dev-websocket-proxy`
- **Action:** Terraform creates via `module.websocket_lambda`

### 6. API Gateway
- ✅ `shelfshack-dev-websocket` (WebSocket API)
- **Action:** Terraform creates via `resource.aws_apigatewayv2_api.websocket`

### 7. ECS Resources
- ✅ Cluster: `shelfshack-dev-cluster`
- ✅ Service: `shelfshack-dev-service`
- ✅ Task Definition: `shelfshack-dev-task`
- ✅ ALB: `shelfshack-dev-alb` (if `enable_load_balancer = true`)
- **Action:** Terraform creates via `module.ecs_service`
- **⚠️ Note:** This will create a NEW service. Old service must be stopped/deleted separately.

### 8. RDS Database
- ✅ `shelfshack-dev-postgres`
- **Action:** Terraform creates via `module.rds`
- **⚠️ CRITICAL:** This creates a NEW database. Data migration is manual (see below).

### 9. CloudWatch Log Groups
- ✅ `/ecs/shelfshack-dev`
- ✅ `/aws/ecs/executioncommand/shelfshack-dev-cluster`
- ✅ `/aws/lambda/shelfshack-dev-websocket-proxy`
- **Action:** Terraform creates these automatically

### 10. VPC & Networking
- ✅ VPC, Subnets, NAT Gateway, Security Groups
- **Action:** Terraform creates via `module.networking`

### 11. OpenSearch EC2 (if enabled)
- ✅ EC2 Instance for OpenSearch
- ✅ Security Groups
- **Action:** Terraform creates via `module.opensearch_ec2`

### 12. Route53 Records (if configured)
- ✅ `api.shelfshack.com` → ALB
- **Action:** Terraform creates via `resource.aws_route53_record.api`

---

## 🔄 Manual Data Migration Required

These require manual data copying/migration:

### 1. ECR Images
**Status:** ❌ **MANUAL**

**Action:** Copy Docker images from old repo to new repo:
```bash
# Pull from old repo
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  506852294788.dkr.ecr.us-east-1.amazonaws.com

docker pull 506852294788.dkr.ecr.us-east-1.amazonaws.com/rentify-dev-repo:latest

# Tag for new repo
docker tag 506852294788.dkr.ecr.us-east-1.amazonaws.com/rentify-dev-repo:latest \
  506852294788.dkr.ecr.us-east-1.amazonaws.com/shelfshack-dev-repo:latest

# Push to new repo (after Terraform creates it)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  506852294788.dkr.ecr.us-east-1.amazonaws.com

docker push 506852294788.dkr.ecr.us-east-1.amazonaws.com/shelfshack-dev-repo:latest
```

### 2. S3 Bucket Data
**Status:** ❌ **MANUAL**

**Action:** Copy files from old bucket to new bucket:
```bash
aws s3 sync s3://rentify-dev-uploads s3://shelfshack-dev-uploads
```

### 3. RDS Database
**Status:** ❌ **MANUAL - CRITICAL**

**Action:** Create snapshot and restore to new database:
```bash
# 1. Create snapshot of old database
aws rds create-db-snapshot \
  --db-instance-identifier rentify-dev-postgres \
  --db-snapshot-identifier rentify-dev-postgres-migration-snapshot

# 2. Wait for snapshot to complete
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier rentify-dev-postgres-migration-snapshot

# 3. After Terraform creates new RDS, restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier shelfshack-dev-postgres \
  --db-snapshot-identifier rentify-dev-postgres-migration-snapshot
```

**⚠️ Alternative:** Use `pg_dump` and `pg_restore` for more control:
```bash
# Export from old database
pg_dump -h <old-rds-endpoint> -U dbadmin_rentify -d rentify_dev > backup.sql

# Import to new database (after Terraform creates it)
psql -h <new-rds-endpoint> -U dbadmin_shelfshack -d shelfshack_dev < backup.sql
```

### 4. DynamoDB Table Data
**Status:** ❌ **MANUAL** (if you have existing WebSocket connections)

**Action:** Export and import data:
```bash
# Export from old table
aws dynamodb scan \
  --table-name rentify-dev-websocket-connections \
  --output json > websocket-connections-backup.json

# Import to new table (after Terraform creates it)
# Use AWS Data Pipeline or write a script to batch-write items
```

---

## 📋 Migration Checklist

### Pre-Terraform (Manual Steps)
- [ ] Create S3 bucket: `shelfshack-terraform-state`
- [ ] Create DynamoDB table: `shelfshack-terraform-locks`
- [ ] Create S3 bucket: `shelfshack-dev-uploads`
- [ ] Create/migrate Secrets Manager secrets
- [ ] Update `envs/dev/backend.tf` with new bucket/table names
- [ ] Update `envs/dev/terraform.tfvars` with `project = "shelfshack"`

### Terraform Apply
- [ ] Run `terraform init` (uses new backend)
- [ ] Run `terraform plan` (review changes)
- [ ] Run `terraform apply` (creates all new resources)

### Post-Terraform (Data Migration)
- [ ] Copy ECR images to new repository
- [ ] Copy S3 bucket data
- [ ] Migrate RDS database (snapshot restore or pg_dump/restore)
- [ ] Migrate DynamoDB data (if needed)
- [ ] Update application configuration to use new resource names
- [ ] Test application with new resources
- [ ] Update CI/CD pipelines to use new ECR repo name

### Cleanup (After Verification)
- [ ] Stop old ECS service: `rentify-dev-service`
- [ ] Delete old ECR repository: `rentify-dev-repo` (after images copied)
- [ ] Delete old S3 buckets (after data copied)
- [ ] Delete old RDS instance (after data migrated)
- [ ] Delete old IAM roles and policies
- [ ] Delete old Lambda functions
- [ ] Delete old API Gateway
- [ ] Delete old CloudWatch log groups

---

## 🎯 Quick Reference

| Resource | Manual? | Terraform? | Data Migration? |
|----------|---------|------------|-----------------|
| Terraform State S3 | ✅ Yes | ❌ No | N/A |
| Terraform Locks DynamoDB | ✅ Yes | ❌ No | N/A |
| Application S3 Bucket | ✅ Yes | ❌ No | ✅ Yes (copy files) |
| Secrets Manager | ✅ Yes | ❌ No | ✅ Yes (copy secrets) |
| ECR Repository | ❌ No | ✅ Yes | ✅ Yes (copy images) |
| IAM Roles/Policies | ❌ No | ✅ Yes | N/A |
| DynamoDB Tables | ❌ No | ✅ Yes | ✅ Yes (if data exists) |
| Lambda Functions | ❌ No | ✅ Yes | N/A |
| API Gateway | ❌ No | ✅ Yes | N/A |
| ECS Resources | ❌ No | ✅ Yes | N/A (new service) |
| RDS Database | ❌ No | ✅ Yes | ✅ Yes (critical!) |
| CloudWatch Logs | ❌ No | ✅ Yes | N/A |
| VPC/Networking | ❌ No | ✅ Yes | N/A |
| OpenSearch EC2 | ❌ No | ✅ Yes | N/A |

---

## 💡 Recommended Approach

1. **For Development:** Use clean migration (create new resources, migrate data)
2. **For Production:** Use Option 2 from the original doc (keep existing resources, import into Terraform, migrate gradually)

---

## ⚠️ Important Notes

1. **Downtime:** ECS service recreation will cause downtime. Plan accordingly.
2. **Database:** RDS migration is the most critical step. Test thoroughly.
3. **DNS:** If using Route53, update DNS records after ALB is created.
4. **CI/CD:** Update GitHub Actions/workflows to use new ECR repo name.
5. **Backups:** Always backup data before migration.
6. **Testing:** Test in dev environment first before applying to prod.

