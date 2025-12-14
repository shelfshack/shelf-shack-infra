#!/bin/bash
# Full OpenSearch System Analysis
# Runs comprehensive diagnostic checks and provides a complete system health report

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev" || exit 1

echo "=========================================="
echo "OPENSEARCH FULL SYSTEM ANALYSIS"
echo "=========================================="
echo "Timestamp: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Run comprehensive diagnosis
echo -e "${YELLOW}1. Running Comprehensive Diagnosis...${NC}"
echo "----------------------------------------"
"$SCRIPT_DIR/comprehensive_diagnosis.sh" || echo -e "${RED}⚠ Comprehensive diagnosis had issues${NC}"
echo ""

# Run deep diagnosis
echo -e "${YELLOW}2. Running Deep Diagnosis...${NC}"
echo "----------------------------------------"
"$SCRIPT_DIR/deep_diagnosis.sh" || echo -e "${RED}⚠ Deep diagnosis had issues${NC}"
echo ""

# Run complete diagnosis
echo -e "${YELLOW}3. Running Complete Diagnosis...${NC}"
echo "----------------------------------------"
"$SCRIPT_DIR/diagnose_opensearch_complete.sh" || echo -e "${RED}⚠ Complete diagnosis had issues${NC}"
echo ""

# Run OpenSearch analysis
echo -e "${YELLOW}4. Running OpenSearch Analysis...${NC}"
echo "----------------------------------------"
"$SCRIPT_DIR/opensearch_analysis.sh" || echo -e "${RED}⚠ OpenSearch analysis had issues${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}Analysis Complete!${NC}"
echo "=========================================="
echo ""
echo "Summary of checks performed:"
echo "  ✅ Infrastructure status"
echo "  ✅ Container health"
echo "  ✅ Network connectivity"
echo "  ✅ Security group rules"
echo "  ✅ OpenSearch endpoints"
echo "  ✅ System resources"
echo ""
echo "For detailed fixes, run:"
echo "  ./scripts/opensearch/analysis/fix_opensearch_complete.sh"
