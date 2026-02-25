# Terraform Operations Guide

## Overview

This document explains how Terraform operations work with this infrastructure setup.

## ✅ Terraform Apply - First Run

**Command:**
```bash
cd /Users/rohitsoni/Desktop/Rohit/Projects/shelf-shack-infra/envs/prod
terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
```

**What happens:**
1. **Creates all resources** from scratch:
   - VPC, subnets, security groups
   - RDS PostgreSQL instance (with deletion protection enabled)
   - ECS cluster, service, task definition
   - API Gateway (HTTP and WebSocket)
   - Lambda functions
   - S3 buckets
   - DynamoDB tables
   - Route53 records
   - IAM roles and policies

2. **ECS Service Deployment:**
   - Creates new task definition
   - Deploys container to ECS
   - Waits for task to get public IP (up to 10 minutes)
   - Updates API Gateway integration URI with the new IP

3. **Final State:**
   - All resources created and running
   - API Gateway pointing to ECS task IP
   - WebSocket Lambda configured with backend URL

---

## ✅ Terraform Apply - Subsequent Runs (Idempotent)

**Command:**
```bash
terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
```

**What happens:**

### 1. **Resource Check (Idempotency)**
- Terraform checks current state vs desired state
- **Existing resources are NOT recreated** (lifecycle rules prevent this)
- Only **updates** are made where needed

### 2. **ECS Service Update**
- If container image or environment variables changed:
  - Creates **new task definition revision**
  - ECS service automatically deploys new tasks
  - Old tasks are gracefully stopped
- If nothing changed:
  - **No action taken** - service continues running

### 3. **API Gateway IP Update**
- `data.external.ecs_task_public_ip` fetches current ECS task IP
- **Only refreshes when task definition changes** (optimized triggers)
- API Gateway integration URI updates automatically:
  ```terraform
  integration_uri = "http://${local.ecs_public_ip}:${var.container_port}/{proxy}"
  ```
- **No recreation** - integration updates in-place (lifecycle rule)

### 4. **WebSocket Lambda Update**
- If `backend_url` changes (due to new ECS IP):
  - Lambda function code updates
  - API Gateway routes remain the same
- If nothing changed:
  - **No action taken**

### 5. **Other Resources**
- **RDS**: Only updates if configuration changed (e.g., deletion_protection)
- **S3**: Only updates bucket policies, CORS, etc. (bucket itself unchanged)
- **DynamoDB**: Only updates table configuration (table itself unchanged)
- **VPC/Networking**: Only updates if configuration changed

**Key Point:** Terraform is **fully idempotent** - running apply multiple times is safe and only updates what changed.

---

## ✅ Terraform Destroy

**Command:**
```bash
./destroy.sh true YOUR_PASSWORD
```

**Why use the script instead of `terraform destroy` directly?**

The RDS instance has **deletion protection enabled** for safety. The script:
1. Removes `destroy_protection` resource from state
2. Runs `terraform apply -target=module.rds` to **disable deletion protection** (sets `deletion_protection = false`)
3. Runs `terraform destroy` to destroy all resources

**What gets destroyed:**
1. **ECS Service** - stops tasks, deletes service
2. **API Gateway** - deletes HTTP and WebSocket APIs
3. **Lambda Functions** - deletes functions and permissions
4. **RDS Instance** - deletes database (after deletion protection disabled)
5. **S3 Buckets** - empties bucket, then deletes (via null_resource provisioner)
6. **DynamoDB Tables** - deletes tables
7. **VPC/Networking** - deletes subnets, security groups, VPC
8. **All other resources** - IAM roles, Route53 records, etc.

**Important:** The script ensures RDS deletion protection is disabled **before** Terraform attempts to destroy it, preventing errors.

---

## 🔄 How Updates Work

### ECS Service Updates

**Triggered by:**
- Container image change
- Environment variable changes
- Task definition changes
- `force_new_deployment = true` in variables

**Process:**
1. New task definition created
2. ECS service detects change
3. Deploys new tasks (rolling update)
4. Old tasks stopped after new ones are healthy
5. API Gateway IP automatically updates via `data.external.ecs_task_public_ip`

### API Gateway IP Updates

**How it works:**
```terraform
# Data source fetches current ECS task IP
data "external" "ecs_task_public_ip" {
  # Only refreshes when task_definition_arn changes
  query = {
    task_def_arn = module.ecs_service.task_definition_arn
  }
}

# API Gateway integration uses the IP
integration_uri = "http://${local.ecs_public_ip}:${var.container_port}/{proxy}"
```

**Lifecycle rule ensures:**
- Integration updates **in-place** (no recreation)
- Changes happen automatically when ECS task IP changes

---

## 📋 Summary

| Operation | First Run | Subsequent Runs | Notes |
|-----------|-----------|-----------------|-------|
| **terraform apply** | Creates all resources | Updates only changed resources | Fully idempotent |
| **ECS Service** | Creates and deploys | Updates if config changed | Auto-updates API Gateway IP |
| **API Gateway** | Creates with initial IP | Updates IP when ECS changes | No recreation needed |
| **RDS** | Creates with deletion protection | Updates if config changed | Protected by default |
| **terraform destroy** | Use `./destroy.sh` | Use `./destroy.sh` | Script handles RDS protection |

---

## ✅ Verification

To verify everything works correctly:

1. **First apply:**
   ```bash
   terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
   ```
   Should create all resources.

2. **Second apply (should be idempotent):**
   ```bash
   terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
   ```
   Should show "No changes" or only show updates to ECS service if image/env changed.

3. **Destroy:**
   ```bash
   ./destroy.sh true YOUR_PASSWORD
   ```
   Should destroy all resources without errors.

---

## 🎯 Key Design Principles

1. **Idempotency**: Multiple applies are safe and only update what changed
2. **No Unnecessary Recreations**: Lifecycle rules prevent resource recreation
3. **Automatic Updates**: API Gateway IP updates automatically when ECS changes
4. **Safety**: RDS deletion protection prevents accidental deletion
5. **Reliability**: Script handles edge cases (RDS protection, S3 emptying)
