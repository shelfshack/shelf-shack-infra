# OpenSearch Management Scripts

This directory contains scripts for managing and troubleshooting OpenSearch on EC2.

## Directory Structure

- **diagnose/**: Diagnostic scripts to check OpenSearch health and configuration
- **fix/**: Scripts to fix common OpenSearch issues
- **test/**: Test scripts to verify OpenSearch connectivity
- **utils/**: Utility scripts for various operations

## Usage

All scripts should be run from the repository root or from `envs/dev/` directory:

```bash
# From repository root
./scripts/opensearch/diagnose/diagnose_opensearch_complete.sh

# From envs/dev
../../scripts/opensearch/diagnose/diagnose_opensearch_complete.sh
```

## Prerequisites

- AWS CLI configured
- Terraform initialized in `envs/dev/`
- OpenSearch EC2 instance deployed

## Script Categories

### Diagnostic Scripts
- `diagnose_opensearch_complete.sh` - Comprehensive diagnosis
- `check_opensearch_status.sh` - Quick status check
- `opensearch_analysis.sh` - Detailed analysis

### Fix Scripts
- `fix_opensearch_complete.sh` - Complete fix workflow
- `ensure_opensearch_running.sh` - Ensure container is running
- `fix_current_container.sh` - Fix current container issues

### Test Scripts
- `test_opensearch_from_ecs.sh` - Test from ECS container
- `test_from_ecs.sh` - General ECS connectivity test

### Utility Scripts
- `quick_check.sh` - Quick health check
- `get_command_result.sh` - Get SSM command results
