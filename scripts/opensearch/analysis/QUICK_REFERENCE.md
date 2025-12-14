# Quick Reference Guide

## Most Common Commands

### 1. Full System Analysis
```bash
./scripts/opensearch/analysis/run_full_analysis.sh
```
**When to use**: First thing when troubleshooting, or regular health checks

### 2. Complete Diagnosis
```bash
./scripts/opensearch/analysis/diagnose_opensearch_complete.sh
```
**When to use**: Need detailed diagnostic information

### 3. Auto-Fix Issues
```bash
./scripts/opensearch/analysis/fix_opensearch_complete.sh
```
**When to use**: After identifying issues, or when system is down

### 4. Check and Fix
```bash
./scripts/opensearch/analysis/check_and_fix_opensearch.sh
```
**When to use**: Quick one-command solution

## Analysis Script Comparison

| Script | Speed | Detail | Use Case |
|--------|-------|--------|----------|
| `run_full_analysis.sh` | Slow | Very High | Complete system check |
| `diagnose_opensearch_complete.sh` | Medium | High | Standard diagnosis |
| `comprehensive_diagnosis.sh` | Medium | High | System-wide check |
| `deep_diagnosis.sh` | Slow | Very High | Deep troubleshooting |
| `opensearch_analysis.sh` | Fast | Medium | OpenSearch-specific |

## Typical Workflow

```bash
# 1. Run full analysis
./scripts/opensearch/analysis/run_full_analysis.sh

# 2. If issues found, apply fixes
./scripts/opensearch/analysis/fix_opensearch_complete.sh

# 3. Verify fixes worked
./scripts/opensearch/analysis/diagnose_opensearch_complete.sh
```

## Quick Health Check

```bash
# One-liner for quick status
./scripts/opensearch/analysis/diagnose_opensearch_complete.sh | grep -E "✅|⚠️|❌"
```
