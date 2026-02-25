# Production Environment

This directory contains the Terraform configuration for the **production** environment.

## 📁 File Organization

### ⭐ Essential Files (Required - Keep These)
- **Terraform files**: `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars`, `backend.tf`
- **Operational script**: `destroy.sh` - Use this to destroy infrastructure
- **Documentation**: `README.md` (this file), `TERRAFORM_OPERATIONS.md`

### 🔧 Utility Files (Optional - Troubleshooting Only)
- **Utility scripts**: Located in `scripts/` directory (for diagnostics and troubleshooting)
- See `scripts/README.md` for details
- **Do not use for normal operations** - only for troubleshooting

### 📚 Documentation Files
- `README.md` - This file (quick reference)
- `docs/TERRAFORM_OPERATIONS.md` - Detailed operations guide (how apply/destroy works)

## Quick Start

### Deploy Infrastructure

```bash
cd /Users/rohitsoni/Desktop/Rohit/Projects/shelf-shack-infra/envs/prod

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
envs/prod/
├── main.tf                    ⭐ Core Terraform files
├── variables.tf               
├── outputs.tf                 
├── terraform.tfvars           ⭐ Environment variables
├── backend.tf                 
├── destroy.sh                 ⭐ Main destroy script
├── README.md                  📚 Quick reference (this file)
├── docs/                      📚 Documentation
│   └── TERRAFORM_OPERATIONS.md 📚 Detailed operations guide
└── scripts/                   🔧 Utility scripts (troubleshooting only)
    ├── README.md             📚 Script documentation
    └── *.sh                   (diagnostic scripts)
```

## Key Files

- **`main.tf`** - Core infrastructure definition
- **`terraform.tfvars`** - Production-specific configuration
- **`destroy.sh`** - Safe destroy script (handles RDS protection)
- **`docs/TERRAFORM_OPERATIONS.md`** - Detailed guide on how operations work

## Utility Scripts

Utility scripts are in the `scripts/` directory. See `scripts/README.md` for details.

**For normal operations, you only need:**
- `terraform apply` - Deploy/update
- `./destroy.sh` - Destroy

## Features

✅ **Idempotent applies** - Safe to run multiple times  
✅ **Automatic ECS updates** - Service updates when config changes  
✅ **Automatic API Gateway IP updates** - IP updates when ECS task changes  
✅ **Safe destroy** - Script handles RDS deletion protection  
✅ **Resource protection** - Prevents accidental destruction  

## Documentation

- **`docs/TERRAFORM_OPERATIONS.md`** - Complete guide on how apply/destroy works
- **`scripts/README.md`** - Utility script documentation
