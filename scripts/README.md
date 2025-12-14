# Scripts Directory

This directory contains utility scripts for managing the infrastructure.

## Structure

- **opensearch/**: OpenSearch management scripts (diagnose, fix, test, utils)
- **dev/**: Dev environment-specific scripts (if any)

## Usage

Scripts are designed to be run from the repository root or from `envs/dev/`:

```bash
# From repository root
./scripts/opensearch/diagnose/diagnose_opensearch_complete.sh

# From envs/dev
../../scripts/opensearch/diagnose/diagnose_opensearch_complete.sh
```

## Script Requirements

Most scripts require:
- AWS CLI configured with appropriate credentials
- Terraform initialized in `envs/dev/`
- Appropriate IAM permissions

See individual script directories for specific requirements.
