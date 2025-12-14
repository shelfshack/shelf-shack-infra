# OpenSearch Analysis Scripts

This directory contains comprehensive scripts for analyzing and diagnosing OpenSearch system health.

## Quick Start

### Run Full Analysis (Recommended)
```bash
# From repository root
./scripts/opensearch/analysis/run_full_analysis.sh

# From envs/dev
../../scripts/opensearch/analysis/run_full_analysis.sh
```

This runs all diagnostic checks and provides a complete system health report.

## Available Analysis Scripts

### 1. `run_full_analysis.sh` ⭐ **START HERE**
**Purpose**: Master script that runs all analysis checks
- Runs comprehensive diagnosis
- Runs deep diagnosis  
- Runs complete diagnosis
- Runs OpenSearch analysis
- Provides summary report

**Usage**:
```bash
./scripts/opensearch/analysis/run_full_analysis.sh
```

### 2. `diagnose_opensearch_complete.sh` ⭐ **MOST COMPREHENSIVE**
**Purpose**: Complete diagnostic check of all OpenSearch components
- Infrastructure status (EC2, ECS, networking)
- Container status and health
- Security group rules
- Network connectivity
- OpenSearch health endpoints
- Container logs

**Usage**:
```bash
./scripts/opensearch/analysis/diagnose_opensearch_complete.sh
```

### 3. `comprehensive_diagnosis.sh`
**Purpose**: Comprehensive system-wide diagnosis
- Checks all components
- Network connectivity
- Resource utilization
- Configuration validation

**Usage**:
```bash
./scripts/opensearch/analysis/comprehensive_diagnosis.sh
```

### 4. `deep_diagnosis.sh`
**Purpose**: Deep dive into system internals
- Detailed container inspection
- Network packet analysis
- Resource usage deep dive
- Performance metrics

**Usage**:
```bash
./scripts/opensearch/analysis/deep_diagnosis.sh
```

### 5. `opensearch_analysis.sh`
**Purpose**: OpenSearch-specific analysis
- Cluster health
- Index status
- Search performance
- Configuration validation

**Usage**:
```bash
./scripts/opensearch/analysis/opensearch_analysis.sh
```

## Fix Scripts

### 6. `fix_opensearch_complete.sh` ⭐ **AUTO-FIX**
**Purpose**: Complete fix workflow for common issues
- Automatically fixes common problems
- Restarts containers if needed
- Verifies fixes

**Usage**:
```bash
./scripts/opensearch/analysis/fix_opensearch_complete.sh
```

### 7. `check_and_fix_opensearch.sh`
**Purpose**: Check and fix in one command
- Runs diagnostics
- Applies fixes if issues found
- Verifies resolution

**Usage**:
```bash
./scripts/opensearch/analysis/check_and_fix_opensearch.sh
```

## Analysis Workflow

### Step 1: Run Full Analysis
```bash
./scripts/opensearch/analysis/run_full_analysis.sh
```

### Step 2: Review Results
- Check for errors or warnings
- Identify specific issues
- Note any failed checks

### Step 3: Apply Fixes (if needed)
```bash
./scripts/opensearch/analysis/fix_opensearch_complete.sh
```

### Step 4: Verify Fixes
```bash
./scripts/opensearch/analysis/diagnose_opensearch_complete.sh
```

## What Gets Checked

### Infrastructure
- ✅ EC2 instance status
- ✅ Instance type and resources
- ✅ Security groups
- ✅ Network configuration
- ✅ VPC and subnets

### Container
- ✅ Docker installation
- ✅ Container status
- ✅ Container logs
- ✅ Resource usage
- ✅ Port binding

### OpenSearch
- ✅ Health endpoint
- ✅ Cluster status
- ✅ Index status
- ✅ Search functionality
- ✅ Configuration

### Network
- ✅ Port 9200 listening
- ✅ Security group rules
- ✅ ECS connectivity
- ✅ Internal network

## Output Format

All scripts provide:
- ✅ Green checkmarks for passing checks
- ⚠️ Yellow warnings for potential issues
- ❌ Red errors for failures
- 📊 Summary statistics
- 🔍 Detailed diagnostic information

## Prerequisites

- AWS CLI configured
- Terraform initialized in `envs/dev/`
- OpenSearch EC2 instance deployed
- Appropriate IAM permissions

## Troubleshooting

If scripts fail:
1. Check AWS credentials: `aws sts get-caller-identity`
2. Verify Terraform state: `cd envs/dev && terraform show`
3. Check instance status: `aws ec2 describe-instances`
4. Review script output for specific errors

## Related Scripts

- **Diagnostic scripts**: `../diagnose/` - Individual diagnostic tools
- **Fix scripts**: `../fix/` - Specific fix scripts
- **Test scripts**: `../test/` - Connectivity tests
- **Utilities**: `../utils/` - Helper utilities
