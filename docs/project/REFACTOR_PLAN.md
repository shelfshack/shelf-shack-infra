# Repository Refactoring Plan

## Current Issues
- 27 shell scripts mixed with Terraform files in `envs/dev/`
- 20+ markdown files mixed with Terraform files
- No clear organization structure
- Hard to find and maintain scripts

## Proposed Structure

```
shelf-shack-infra/
├── docs/
│   ├── dev/                    # Dev environment docs
│   │   ├── opensearch/         # OpenSearch-specific docs
│   │   └── troubleshooting/    # Troubleshooting guides
│   └── [existing docs]         # Keep existing docs
├── scripts/
│   ├── opensearch/             # OpenSearch management scripts
│   │   ├── diagnose/           # Diagnostic scripts
│   │   ├── fix/                # Fix scripts
│   │   └── test/               # Test scripts
│   ├── dev/                    # Dev environment scripts
│   └── [existing scripts]      # Keep existing scripts
└── envs/
    └── dev/                    # Only Terraform files
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── terraform.tfvars
        └── backend.tf
```

## File Categories

### Shell Scripts (27 files)
- **Diagnostic**: diagnose_opensearch*.sh, check_opensearch*.sh, comprehensive_diagnosis.sh, deep_diagnosis.sh, opensearch_analysis.sh
- **Fix**: fix_opensearch*.sh, fix_docker*.sh, fix_current_container.sh, ensure_opensearch_running.sh, restart_opensearch_now.sh
- **Test**: test_opensearch*.sh, test_from_ecs.sh
- **Utility**: get_command_result.sh, quick_check.sh, access_via_bastion.sh, architect_solution.sh

### Markdown Files (20+ files)
- **Troubleshooting**: FINAL_ANALYSIS.md, ROOT_CAUSE_AND_FIX.md, senior_architect_analysis.md, opensearch_root_cause_analysis.md
- **Fix Guides**: FIX_*.md, COMPLETE_SOLUTION.md, FINAL_FIX_*.md
- **Configuration**: BEST_INSTANCE_CHOICE.md, FREE_TIER_EC2_INFO.md, UPGRADE_TO_T3_SMALL.md, MEMORY_FIX_SUMMARY.md
- **Status**: BASTION_DISABLED_SUMMARY.md, ALL_CHANGES_MADE.md

## Migration Steps
1. Create new directory structure
2. Move and organize scripts
3. Move and organize markdown files
4. Update script paths if needed
5. Create README files for each directory
6. Clean up envs/dev/ to only contain Terraform files
