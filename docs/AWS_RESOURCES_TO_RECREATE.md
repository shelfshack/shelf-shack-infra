# AWS Resources to Recreate After Renaming from "rentify" to "shelfshack"

After updating Terraform code from "rentify" to "shelfshack", you need to recreate or migrate the following AWS resources.

## Resource Naming Pattern

All resources use the pattern: `${project}-${environment}` where:
- `project` = `shelfshack` (was `rentify`)
- `environment` = `dev` (or `prod`)

So `local.name` = `shelfshack-dev` (was `rentify-dev`)

## Resources That Need to Be Recreated

### 1. ECR Repository

**Old Name:** `rentify-dev-repo`  
**New Name:** `shelfshack-dev-repo`

**Action:** 
- Option A: Create new repo and push images
- Option B: Keep old repo and update Terraform to reference it

### 2. S3 Buckets

**Old Names:**
- `rentify-dev-uploads` (for application uploads)
- `rentify-terraform-state` (for Terraform state backend)
- `rentify-terraform-locks` (DynamoDB table for state locking)

**New Names:**
- `shelfshack-dev-uploads` (for application uploads)
- `shelfshack-terraform-state` (for Terraform state backend)
- `shelfshack-terraform-locks` (DynamoDB table for state locking)

**Action:**
- Create new buckets
- Migrate data from old buckets if needed
- Update backend configuration

### 3. IAM Roles

**Old Names:**
- `rentify-dev-execution-role` (ECS task execution role)
- `rentify-dev-task-role` (ECS task role)
- `rentify-dev-websocket-lambda-role` (Lambda execution role)

**New Names:**
- `shelfshack-dev-execution-role` (ECS task execution role)
- `shelfshack-dev-task-role` (ECS task role)
- `shelfshack-dev-websocket-lambda-role` (Lambda execution role)

**Action:**
- Terraform will create these automatically
- Old roles can be deleted after migration

### 4. IAM Policies

**Old Names:**
- `rentify-dev-execution-secrets` (Secrets Manager access)
- `rentify-dev-task-s3` (S3 access)
- `rentify-dev-lambda-dynamodb-policy` (DynamoDB access)
- `rentify-dev-lambda-apigw-policy` (API Gateway access)

**New Names:**
- `shelfshack-dev-execution-secrets` (Secrets Manager access)
- `shelfshack-dev-task-s3` (S3 access)
- `shelfshack-dev-lambda-dynamodb-policy` (DynamoDB access)
- `shelfshack-dev-lambda-apigw-policy` (API Gateway access)

**Action:**
- Terraform will create these automatically

### 5. DynamoDB Tables

**Old Names:**
- `rentify-dev-websocket-connections` (WebSocket connections)
- `rentify-terraform-locks` (Terraform state locking)

**New Names:**
- `shelfshack-dev-websocket-connections` (WebSocket connections)
- `shelfshack-terraform-locks` (Terraform state locking)

**Action:**
- Terraform will create these automatically
- Migrate data if needed

### 6. Lambda Functions

**Old Name:** `rentify-dev-websocket-proxy`  
**New Name:** `shelfshack-dev-websocket-proxy`

**Action:**
- Terraform will create this automatically

### 7. API Gateway

**Old Name:** `rentify-dev-websocket`  
**New Name:** `shelfshack-dev-websocket`

**Action:**
- Terraform will create this automatically

### 8. ECS Resources

**Old Names:**
- Cluster: `rentify-dev-cluster`
- Service: `rentify-dev-service`
- Task Definition: `rentify-dev-task`
- ALB: `rentify-dev-alb` (if enabled)

**New Names:**
- Cluster: `shelfshack-dev-cluster`
- Service: `shelfshack-dev-service`
- Task Definition: `shelfshack-dev-task`
- ALB: `shelfshack-dev-alb` (if enabled)

**Action:**
- Terraform will create these automatically
- **Important:** You'll need to migrate running tasks/services

### 9. RDS Database

**Old Name:** `rentify-dev-postgres`  
**New Name:** `shelfshack-dev-postgres`

**Action:**
- **CRITICAL:** This is a database - don't recreate without migration!
- Option A: Keep old name and update Terraform to reference it
- Option B: Create snapshot, restore to new name, migrate data

### 10. Secrets Manager

**Old ARN Pattern:** `arn:aws:secretsmanager:...:secret:rentify/...`  
**New ARN Pattern:** `arn:aws:secretsmanager:...:secret:shelfshack/...`

**Action:**
- Update secret names in AWS Secrets Manager
- Or keep old names and update Terraform to reference them

### 11. CloudWatch Log Groups

**Old Names:**
- `/ecs/rentify-dev`
- `/aws/ecs/executioncommand/rentify-dev-cluster`
- `/aws/lambda/rentify-dev-websocket-proxy`

**New Names:**
- `/ecs/shelfshack-dev`
- `/aws/ecs/executioncommand/shelfshack-dev-cluster`
- `/aws/lambda/shelfshack-dev-websocket-proxy`

**Action:**
- Terraform will create these automatically

## Migration Strategy

### Option 1: Clean Migration (Recommended for New Deployments)

1. **Create new resources** with new names
2. **Migrate data:**
   - Copy S3 bucket contents
   - Export/import ECR images
   - Migrate database (if recreating)
3. **Update Terraform state** to point to new resources
4. **Delete old resources** after verification

### Option 2: Keep Existing Resources (Recommended for Production)

1. **Update Terraform code** to reference existing resource names
2. **Import existing resources** into Terraform state:
   ```bash
   terraform import aws_ecr_repository.this rentify-dev-repo
   terraform import aws_s3_bucket.uploads rentify-dev-uploads
   # etc.
   ```
3. **Gradually migrate** resources over time

### Option 3: Hybrid Approach

1. **Keep critical resources** (RDS, S3 data) with old names
2. **Recreate non-critical resources** (roles, policies, Lambda) with new names
3. **Update Terraform** to reference both old and new names

## Quick Reference: All Resource Names

### Current (rentify-dev):
- ECR: `rentify-dev-repo`
- S3: `rentify-dev-uploads`, `rentify-terraform-state`
- DynamoDB: `rentify-dev-websocket-connections`, `rentify-terraform-locks`
- IAM Roles: `rentify-dev-execution-role`, `rentify-dev-task-role`, `rentify-dev-websocket-lambda-role`
- Lambda: `rentify-dev-websocket-proxy`
- ECS: `rentify-dev-cluster`, `rentify-dev-service`, `rentify-dev-task`
- RDS: `rentify-dev-postgres`
- API Gateway: `rentify-dev-websocket`

### New (shelfshack-dev):
- ECR: `shelfshack-dev-repo`
- S3: `shelfshack-dev-uploads`, `shelfshack-terraform-state`
- DynamoDB: `shelfshack-dev-websocket-connections`, `shelfshack-terraform-locks`
- IAM Roles: `shelfshack-dev-execution-role`, `shelfshack-dev-task-role`, `shelfshack-dev-websocket-lambda-role`
- Lambda: `shelfshack-dev-websocket-proxy`
- ECS: `shelfshack-dev-cluster`, `shelfshack-dev-service`, `shelfshack-dev-task`
- RDS: `shelfshack-dev-postgres`
- API Gateway: `shelfshack-dev-websocket`

## Important Notes

1. **Terraform State:** If you're using S3 backend, you'll need to create the new state bucket first
2. **Database:** Don't recreate RDS without proper backup and migration
3. **Running Services:** ECS services will need to be recreated, causing downtime
4. **DNS/Route53:** If using custom domains, update those references too
5. **Secrets:** Update secret ARNs in Secrets Manager or update Terraform to reference old names

## Recommended Approach

For **production systems**, use **Option 2** (keep existing resources) to avoid downtime. Update Terraform to reference existing resource names and import them into state.

For **development/test**, use **Option 1** (clean migration) to start fresh with new naming.


