#!/bin/bash

# Test GitHub connectivity from EC2 instance
# Run this script on the EC2 instance to verify it can reach GitHub
# Based on GitHub's self-hosted runner network requirements

echo "========================================================"
echo "Testing GitHub Self-Hosted Runner Network Connectivity"
echo "========================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SUCCESS_COUNT=0
FAIL_COUNT=0

test_connectivity() {
    local domain=$1
    local description=$2
    
    echo ""
    echo "Testing: $description"
    echo "  Domain: $domain"
    
    # Test DNS resolution
    if nslookup $domain > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ DNS resolution successful${NC}"
    else
        echo -e "  ${RED}❌ DNS resolution failed${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
    
    # Test HTTPS connectivity
    if timeout 10 curl -Is https://$domain --connect-timeout 10 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ HTTPS (443) connection successful${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        echo -e "  ${RED}❌ HTTPS (443) connection failed${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

echo ""
echo "========================================================"
echo "Core GitHub Domains"
echo "========================================================"

# Core GitHub domains
test_connectivity "github.com" "Main GitHub website"
test_connectivity "api.github.com" "GitHub API"
test_connectivity "codeload.github.com" "Code & Actions downloads"

echo ""
echo "========================================================"
echo "GitHub Actions Infrastructure"
echo "========================================================"

# GitHub Actions domains
test_connectivity "pipelines.actions.githubusercontent.com" "Runner communication"
test_connectivity "results-receiver.actions.githubusercontent.com" "Job results submission"
test_connectivity "vstoken.actions.githubusercontent.com" "OIDC token service"

echo ""
echo "========================================================"
echo "Artifact & Cache Storage"
echo "========================================================"

# Storage domains
test_connectivity "productionresults.blob.core.windows.net" "Artifact/cache storage (Azure)"
test_connectivity "artifacts.actions.githubusercontent.com" "Artifacts service"

echo ""
echo "========================================================"
echo "Runner Updates & Releases"
echo "========================================================"

# Runner update domains
test_connectivity "objects.githubusercontent.com" "GitHub objects/assets"
test_connectivity "github-releases.githubusercontent.com" "GitHub releases"
test_connectivity "github-registry-files.githubusercontent.com" "Registry files"

echo ""
echo "========================================================"
echo "GitHub Packages & Container Registry"
echo "========================================================"

# Packages domains
test_connectivity "ghcr.io" "GitHub Container Registry"
test_connectivity "pkg-containers.githubusercontent.com" "Package containers"

echo ""
echo "========================================================"
echo "Additional Connectivity Tests"
echo "========================================================"

# Test GitHub API with actual API call
echo ""
echo "Testing GitHub API (actual call)..."
GITHUB_ZEN=$(curl -s https://api.github.com/zen --connect-timeout 10)
if [ -n "$GITHUB_ZEN" ]; then
    echo -e "  ${GREEN}✅ GitHub API is accessible${NC}"
    echo "  API Response: $GITHUB_ZEN"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    echo -e "  ${RED}❌ GitHub API is not accessible${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check NAT Gateway / Internet connectivity
echo ""
echo "Testing outbound internet connectivity..."
PUBLIC_IP=$(curl -s --connect-timeout 10 ifconfig.me)
if [ -n "$PUBLIC_IP" ]; then
    echo -e "  ${GREEN}✅ Outbound connectivity working${NC}"
    echo "  Public IP (via NAT): $PUBLIC_IP"
else
    echo -e "  ${RED}❌ No outbound internet connectivity${NC}"
fi

# Check DNS servers
echo ""
echo "DNS Configuration:"
cat /etc/resolv.conf | grep nameserver

# Check routing table
echo ""
echo "Routing Table:"
ip route show

echo ""
echo "========================================================"
echo "Summary"
echo "========================================================"
echo -e "Successful tests: ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "Failed tests: ${RED}$FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All connectivity tests passed!${NC}"
    echo "The runner should be able to communicate with GitHub."
    exit 0
else
    echo -e "${RED}❌ Some connectivity tests failed!${NC}"
    echo "The runner may have issues communicating with GitHub."
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Verify NAT Gateway is running and has an Elastic IP"
    echo "2. Check route table for private subnet points to NAT Gateway"
    echo "3. Verify Security Group allows outbound HTTPS (443)"
    echo "4. Check Network ACLs allow outbound traffic"
    exit 1
fi
