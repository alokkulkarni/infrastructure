#!/bin/bash

# Test GitHub connectivity from EC2 instance
# Run this script on the EC2 instance to verify it can reach GitHub

echo "Testing GitHub Connectivity..."
echo "======================================"

# Test DNS resolution
echo "1. Testing DNS resolution for github.com..."
if nslookup github.com > /dev/null 2>&1; then
    echo "✅ DNS resolution successful"
    nslookup github.com | grep -A 2 "Name:"
else
    echo "❌ DNS resolution failed"
fi

echo ""
echo "2. Testing HTTPS connection to github.com..."
if curl -Is https://github.com --connect-timeout 10 | head -1; then
    echo "✅ HTTPS connection successful"
else
    echo "❌ HTTPS connection failed"
fi

echo ""
echo "3. Testing GitHub API..."
if curl -s https://api.github.com/zen --connect-timeout 10; then
    echo ""
    echo "✅ GitHub API accessible"
else
    echo "❌ GitHub API not accessible"
fi

echo ""
echo "4. Testing GitHub Actions API..."
if curl -s -I https://api.github.com/repos/alokkulkarni/sit-test-repo/actions/runners --connect-timeout 10 | head -1; then
    echo "✅ GitHub Actions API accessible"
else
    echo "❌ GitHub Actions API not accessible"
fi

echo ""
echo "5. Checking default route and NAT gateway..."
ip route show
echo ""
echo "6. Testing outbound connectivity..."
curl -s ifconfig.me
echo ""

echo "======================================"
echo "Connectivity test complete"
