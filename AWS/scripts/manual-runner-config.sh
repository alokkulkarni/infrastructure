#!/bin/bash
# Manual runner configuration script
# Run this inside the EC2 instance via SSM

set -e

# Configuration
GITHUB_REPO_URL="https://github.com/alokkulkarni/sit-test-repo"
RUNNER_NAME="aws-ec2-runner-SIT-Alok-TeamA-20251121-1146-manual"
RUNNER_LABELS="self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251121-1146"
RUNNER_TOKEN="AAIZMKGJKOZMW6ZZSPFVHKTJEBSDG"  # Replace with fresh token if needed

echo "========================================"
echo "Configuring GitHub Actions Runner"
echo "========================================"
echo "Repository: $GITHUB_REPO_URL"
echo "Runner Name: $RUNNER_NAME"
echo "Labels: $RUNNER_LABELS"
echo "========================================"

# Switch to runner user
sudo su - runner << 'EOF'
cd /home/runner/actions-runner

# Remove any existing configuration
if [ -f ".runner" ]; then
    echo "Removing existing runner configuration..."
    ./config.sh remove --token "${RUNNER_TOKEN}" || true
fi

# Configure the runner
echo "Configuring runner..."
./config.sh \
    --url "${GITHUB_REPO_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --unattended \
    --replace

if [ $? -eq 0 ]; then
    echo "✅ Runner configuration successful"
    
    # Verify registration file
    if [ -f ".runner" ]; then
        echo "✅ Runner registration file created:"
        cat .runner | jq '.' 2>/dev/null || cat .runner
    fi
else
    echo "❌ Runner configuration failed"
    exit 1
fi
EOF

# Install and start runner service
echo "========================================"
echo "Installing runner service..."
echo "========================================"
cd /home/runner/actions-runner
sudo ./svc.sh install runner
sudo ./svc.sh start

echo "========================================"
echo "✅ Runner configured and started!"
echo "========================================"
sudo ./svc.sh status
