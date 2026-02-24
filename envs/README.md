# Terraform Environments

This directory contains Terraform configurations for different environments.

## 📁 Directory Structure

```
envs/
├── prod/                    Production environment
│   ├── *.tf                ⭐ Core Terraform files
│   ├── destroy.sh          ⭐ Main destroy script
│   ├── README.md           📚 Quick reference
│   ├── docs/               📚 Documentation
│   │   └── TERRAFORM_OPERATIONS.md
│   └── scripts/            🔧 Utility scripts (troubleshooting)
│
└── dev/                     Development environment
    ├── *.tf                ⭐ Core Terraform files
    ├── destroy.sh          ⭐ Main destroy script
    ├── README.md           📚 Quick reference
    └── scripts/            🔧 Utility scripts (if needed)
```

## 🚀 Quick Start

### Production
```bash
cd envs/prod
terraform apply -var-file=terraform.tfvars -var="db_master_password=..." -auto-approve
./destroy.sh true YOUR_PASSWORD
```

### Development
```bash
cd envs/dev
terraform apply -var-file=terraform.tfvars -var="db_master_password=..." -auto-approve
./destroy.sh true YOUR_PASSWORD
```

## 📋 Essential Files

Each environment directory contains:

### ⭐ Required Files (Keep in Root)
- `main.tf` - Main infrastructure configuration
- `variables.tf` - Variable definitions
- `outputs.tf` - Output values
- `terraform.tfvars` - Environment variables
- `backend.tf` - State backend configuration
- `destroy.sh` - Main destroy script ⭐
- `README.md` - Quick start guide

### 📚 Documentation
- `README.md` - Quick start guide (in each env directory)
- `docs/TERRAFORM_OPERATIONS.md` (prod only) - Detailed operations guide

### 🔧 Utility Scripts (Optional - Troubleshooting Only)
- Located in `scripts/` directory
- See `scripts/README.md` for details
- **Not needed for normal operations**

## 🧹 Organization

**Production:** Run `./organize_files.sh` to organize utility scripts into `scripts/` directory.

**Development:** Already clean and organized.

## 📚 Documentation

- **`envs/prod/README.md`** - Production quick start
- **`envs/dev/README.md`** - Development quick start
- **`envs/prod/docs/TERRAFORM_OPERATIONS.md`** - Detailed operations guide

## ✅ Features (Both Environments)

- ✅ Idempotent `terraform apply` - Safe to run multiple times
- ✅ Automatic ECS updates - Service updates when config changes
- ✅ Automatic API Gateway IP updates - IP updates when ECS task changes
- ✅ Safe destroy - Script handles RDS deletion protection
- ✅ Resource protection - Prevents accidental destruction
