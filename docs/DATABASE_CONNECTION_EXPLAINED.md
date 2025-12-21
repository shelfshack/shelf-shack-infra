# Where "rentify-dev-postgres" is Used for Database Connection

## Overview

The name "rentify-dev-postgres" (or "shelfshack-dev-postgres" after rename) appears in **two places**:

1. **RDS Instance Identifier** (AWS resource name)
2. **Database Connection String** (in Secrets Manager)

## 1. RDS Instance Identifier

**Location:** Terraform configuration

**File:** `modules/rds_postgres/main.tf` (line 40)

```hcl
resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"  # Creates: rentify-dev-postgres
  # ...
}
```

**What it is:**
- The AWS RDS instance identifier (resource name)
- Used by AWS to identify the database instance
- **NOT directly used in connection strings**

**After rename:**
- Will become: `shelfshack-dev-postgres`

## 2. Database Connection String

**Location:** AWS Secrets Manager

**Secret ARN:** `arn:aws:secretsmanager:us-east-1:506852294788:secret:shelfshack/db_url-9ixzM1:DATABASE_URL::`

**What it contains:**
The `DATABASE_URL` secret contains a connection string like:
```
postgresql://username:password@rentify-dev-postgres.cqny48w269rg.us-east-1.rds.amazonaws.com:5432/dbname
```

**Where the hostname comes from:**
- AWS automatically creates an RDS endpoint using the instance identifier
- Format: `{instance-identifier}.{random-id}.{region}.rds.amazonaws.com`
- Example: `rentify-dev-postgres.cqny48w269rg.us-east-1.rds.amazonaws.com`

## How the Application Connects

### Step 1: Terraform Creates RDS
```hcl
# modules/rds_postgres/main.tf
resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"  # rentify-dev-postgres
  # ...
}
```

### Step 2: Connection String Stored in Secrets Manager
The connection string is stored in AWS Secrets Manager with the RDS endpoint:
```
postgresql://dbadmin_shelfshack:password@rentify-dev-postgres.cqny48w269rg.us-east-1.rds.amazonaws.com:5432/shelfshack
```

### Step 3: ECS Task Gets Secret
```hcl
# envs/dev/terraform.tfvars
app_secrets = [
  {
    name       = "DATABASE_URL"
    value_from = "arn:aws:secretsmanager:...:secret:shelfshack/db_url-9ixzM1:DATABASE_URL::"
  }
]
```

### Step 4: Application Reads Environment Variable
```python
# app/databases/database.py
database_url = settings.database_url  # From DATABASE_URL env var
engine = create_engine(database_url)
```

## Where to Update After Rename

### ✅ Already Updated in Terraform Code:
- `modules/rds_postgres/main.tf` - Will create `shelfshack-dev-postgres` instance
- `envs/dev/terraform.tfvars` - Secret ARN updated to `shelfshack/db_url`

### ⚠️ Needs Manual Update in AWS:

1. **AWS Secrets Manager Secret:**
   - Secret name: `shelfshack/db_url` (or `rentify/db_url` if still using old name)
   - **Action:** Update the `DATABASE_URL` value in the secret to use new RDS endpoint
   - New endpoint will be: `shelfshack-dev-postgres.{random-id}.us-east-1.rds.amazonaws.com`

2. **RDS Instance:**
   - **Option A:** Create new RDS instance with name `shelfshack-dev-postgres` and migrate data
   - **Option B:** Keep existing `rentify-dev-postgres` instance and update Terraform to reference it

## Current Connection Flow

```
Terraform (creates)
    ↓
RDS Instance: rentify-dev-postgres
    ↓
AWS generates endpoint: rentify-dev-postgres.cqny48w269rg.us-east-1.rds.amazonaws.com
    ↓
Connection string stored in Secrets Manager: shelfshack/db_url
    ↓
ECS Task Definition (reads secret)
    ↓
Environment Variable: DATABASE_URL
    ↓
Application Code (app/databases/database.py)
    ↓
SQLAlchemy Engine (connects to database)
```

## After Rename to "shelfshack"

```
Terraform (creates)
    ↓
RDS Instance: shelfshack-dev-postgres
    ↓
AWS generates endpoint: shelfshack-dev-postgres.{random-id}.us-east-1.rds.amazonaws.com
    ↓
Connection string stored in Secrets Manager: shelfshack/db_url
    ↓
ECS Task Definition (reads secret)
    ↓
Environment Variable: DATABASE_URL
    ↓
Application Code (app/databases/database.py)
    ↓
SQLAlchemy Engine (connects to database)
```

## Important Notes

1. **The application code doesn't hardcode the database name** - it reads from `DATABASE_URL` environment variable

2. **The RDS instance identifier affects:**
   - The AWS resource name
   - The automatically generated RDS endpoint hostname
   - The connection string in Secrets Manager

3. **To update the connection string:**
   - After creating new RDS instance, update the `DATABASE_URL` secret in Secrets Manager
   - Or keep old instance and update Terraform to reference it

4. **The secret ARN in terraform.tfvars** already points to `shelfshack/db_url`, but the actual secret value needs to contain the correct RDS endpoint

## Summary

- **RDS Instance Name:** Defined in Terraform (`modules/rds_postgres/main.tf`)
- **Connection String:** Stored in AWS Secrets Manager (`shelfshack/db_url`)
- **Application:** Reads from `DATABASE_URL` environment variable (from Secrets Manager)
- **No hardcoded references** in application code - everything comes from environment variables



