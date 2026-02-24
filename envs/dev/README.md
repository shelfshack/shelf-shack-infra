# Development Environment

This directory contains the Terraform configuration for the **development** environment.

## 📁 File Organization

### ⭐ Essential Files (Required)
- **Terraform files**: `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars`, `backend.tf`
- **Operational script**: `destroy.sh` - Use this to destroy infrastructure
- **Documentation**: `README.md` (this file)

### 🔧 Utility Files (Optional)
- **Utility scripts**: Located in `scripts/` directory (if needed for troubleshooting)
- Dev environment is clean - no utility scripts unless troubleshooting

## Quick Start

### Deploy Infrastructure

```bash
cd /Users/rohitsoni/Desktop/Rohit/Projects/shelf-shack-infra/envs/dev

terraform apply \
  -var-file=terraform.tfvars \
  -var="db_master_password=YOUR_PASSWORD" \
  -auto-approve
```

### Update Infrastructure (Idempotent)

```bash
terraform apply \
  -var-file=terraform.tfvars \
  -var="db_master_password=YOUR_PASSWORD" \
  -auto-approve
```

Running `terraform apply` multiple times is safe - it only updates what changed.

### Destroy Infrastructure

```bash
./destroy.sh true YOUR_PASSWORD
```

**Important:** Always use `./destroy.sh` instead of `terraform destroy` directly. The script handles RDS deletion protection automatically.

## Directory Structure

```
envs/dev/
├── main.tf                    ⭐ Core Terraform files
├── variables.tf               
├── outputs.tf                 
├── terraform.tfvars           ⭐ Environment variables
├── backend.tf                 
├── destroy.sh                 ⭐ Main destroy script
├── README.md                  📚 Quick reference (this file)
└── scripts/                   🔧 Utility scripts (if needed)
    └── README.md             📚 Script documentation
```

## Key Files

- **`main.tf`** - Core infrastructure definition
- **`terraform.tfvars`** - Development-specific configuration
- **`destroy.sh`** - Safe destroy script (handles RDS protection)

## Features

✅ **Idempotent applies** - Safe to run multiple times  
✅ **Automatic ECS updates** - Service updates when config changes  
✅ **Automatic API Gateway IP updates** - IP updates when ECS task changes  
✅ **Safe destroy** - Script handles RDS deletion protection  
✅ **Resource protection** - Prevents accidental destruction  

## Differences from Production

- Uses development-specific resource names and configurations
- May have different scaling, backup, or monitoring settings
- Uses development AWS account/region as configured

## Documentation

See `../prod/TERRAFORM_OPERATIONS.md` for detailed operations guide (same principles apply to dev).
