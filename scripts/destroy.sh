#!/bin/bash

# Script to destroy Terraform infrastructure
# Usage: ./scripts/destroy.sh [dev|prod] [db_master_password]
#
# This script delegates to the environment-specific destroy.sh scripts
# which handle destroy protection, RDS deletion protection, and S3 bucket emptying.

set -e

ENVIRONMENT="${1:-dev}"
DB_PASSWORD="${2:-}"

if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "Error: Environment must be 'dev' or 'prod'"
    exit 1
fi

ENV_DIR="$(dirname "$0")/../envs/$ENVIRONMENT"
DESTROY_SCRIPT="$ENV_DIR/destroy.sh"

if [ ! -f "$DESTROY_SCRIPT" ]; then
    echo "Error: Destroy script not found at $DESTROY_SCRIPT"
    exit 1
fi

if [ ! -x "$DESTROY_SCRIPT" ]; then
    echo "Making destroy script executable..."
    chmod +x "$DESTROY_SCRIPT"
fi

echo "========================================="
echo "Destroying Terraform Infrastructure"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "========================================="
echo ""

# Delegate to the environment-specific destroy script
# It requires: ./destroy.sh true [db_master_password]
if [ -n "$DB_PASSWORD" ]; then
    "$DESTROY_SCRIPT" true "$DB_PASSWORD"
else
    echo "⚠️  Warning: No database password provided."
    echo "   Usage: ./scripts/destroy.sh $ENVIRONMENT YOUR_PASSWORD"
    echo ""
    echo "   Or run directly:"
    echo "   cd $ENV_DIR && ./destroy.sh true YOUR_PASSWORD"
    exit 1
fi

echo ""
echo "========================================="
echo "Destroy Complete!"
echo "========================================="

