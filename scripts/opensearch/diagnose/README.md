# Diagnostic Scripts

Scripts to diagnose OpenSearch issues and check system health.

## Available Scripts

- **diagnose_opensearch_complete.sh** - Comprehensive diagnosis (recommended)
- **diagnose_opensearch.sh** - Basic diagnosis
- **check_opensearch_status.sh** - Quick status check
- **check_opensearch_simple.sh** - Simple health check
- **check_opensearch_final.sh** - Final verification
- **comprehensive_diagnosis.sh** - Full system diagnosis
- **deep_diagnosis.sh** - Deep dive analysis
- **opensearch_analysis.sh** - Detailed analysis

## Usage

```bash
# From repository root
./scripts/opensearch/diagnose/diagnose_opensearch_complete.sh

# From envs/dev
../../scripts/opensearch/diagnose/diagnose_opensearch_complete.sh
```

## What They Check

- OpenSearch container status
- Port listening status
- Security group rules
- Network connectivity
- Health endpoints
- Container logs
