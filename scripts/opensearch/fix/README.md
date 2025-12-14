# Fix Scripts

Scripts to fix common OpenSearch issues.

## Available Scripts

- **fix_opensearch_complete.sh** - Complete fix workflow (recommended)
- **fix_opensearch_comprehensive.sh** - Comprehensive fix
- **ensure_opensearch_running.sh** - Ensure container is running
- **fix_current_container.sh** - Fix current container
- **fix_docker_and_opensearch.sh** - Fix Docker and OpenSearch
- **fix_opensearch_container.sh** - Fix container configuration
- **restart_opensearch_now.sh** - Restart container

## Usage

```bash
# From repository root
./scripts/opensearch/fix/fix_opensearch_complete.sh

# From envs/dev
../../scripts/opensearch/fix/fix_opensearch_complete.sh
```

## Common Fixes

- Container not running
- Memory issues
- Configuration errors
- Network connectivity
- Docker installation
