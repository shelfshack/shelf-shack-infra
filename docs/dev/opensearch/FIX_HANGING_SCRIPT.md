# Fix: User Data Script Hanging

## Problem Identified
The user_data script is hanging at "Verifying container started..." because:
1. Container started but likely crashed immediately
2. The `docker ps` check in the script is waiting/hanging
3. Using `latest` tag (OpenSearch 3.x) which may be too resource-intensive

## Root Cause
The container ID was created (`d1a1e5148398fa7ab0b596240d3bf16f5bc2096a2eb48e3e6662559d30ecdc33`) but the script hangs when checking if it's running. This suggests the container crashed.

## Solution: Fix the user_data Script

The script needs to:
1. Not hang if container check fails
2. Show container logs if it fails
3. Use specific version (2.11.0) instead of latest

## Immediate Fix

Update the user_data script to handle container failures better and use the version from variables.
