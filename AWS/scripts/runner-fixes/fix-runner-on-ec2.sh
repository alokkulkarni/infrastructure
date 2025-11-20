#!/bin/bash
set -e

# Define log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting runner configuration fix..."

# Setup GitHub Actions Runner
log "Setting up GitHub Actions Runner..."

# Runner should already be downloaded, but let's check
RUNNER_HOME="/home/runner"
RUNNER_DIR="$RUNNER_HOME/actions-runner"

if [ ! -d "$RUNNER_DIR" ]; then
    log "Runner directory doesn't exist, creating and downloading..."
    
    # Create runner user if doesn't exist
    if ! id runner &>/dev/null; then
        useradd -m -s /bin/bash runner
        usermod -aG docker runner
    fi
    
    mkdir -p $RUNNER_DIR
    cd $RUNNER_DIR
    
    # Download the latest runner package
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
    curl -o actions-runner-linux-x64-$RUNNER_VERSION.tar.gz -L \
      https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
    
    tar xzf ./actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
    rm actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
    
    chown -R runner:runner $RUNNER_DIR
fi

cd $RUNNER_DIR

# Get configuration from terraform or prompt
GITHUB_REPO_URL="${1:-https://github.com/alokkulkarni/sit-test-repo}"
RUNNER_TOKEN="${2}"
RUNNER_NAME="${3:-aws-ec2-runner-SIT-Alok-TeamA-20251120-1751}"
RUNNER_LABELS="${4:-self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251120-1751}"

log "Runner configuration:"
log "  Repository URL: $GITHUB_REPO_URL"
log "  Runner Name: $RUNNER_NAME"
log "  Runner Labels: $RUNNER_LABELS"
log "  Token provided: $(if [ -n "$RUNNER_TOKEN" ] && [ "$RUNNER_TOKEN" != "" ]; then echo 'YES'; else echo 'NO'; fi)"

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "" ]; then
    log "ERROR: No runner token provided!"
    log "Usage: $0 <repo_url> <token> [runner_name] [labels]"
    exit 1
fi

log "Testing GitHub connectivity..."
if ! timeout 10 curl -Is https://github.com > /dev/null 2>&1; then
    log "ERROR: Cannot reach github.com"
    exit 1
fi
log "✅ GitHub connectivity OK"

# Remove existing runner if configured
if [ -f ".runner" ]; then
    log "Removing existing runner configuration..."
    sudo -u runner bash << 'EOF'
cd /home/runner/actions-runner
./config.sh remove --token "$RUNNER_TOKEN" || true
EOF
fi

# Configure runner as runner user
log "Configuring runner..."
sudo -u runner bash << EOF
cd $RUNNER_DIR
./config.sh \
    --url $GITHUB_REPO_URL \
    --token $RUNNER_TOKEN \
    --name $RUNNER_NAME \
    --labels $RUNNER_LABELS \
    --unattended \
    --replace

if [ \$? -eq 0 ]; then
    echo "✅ Runner configuration successful"
    
    if [ -f ".runner" ]; then
        echo "✅ Runner registration file created"
        cat .runner
    else
        echo "⚠️  WARNING: Runner registration file not found"
    fi
else
    echo "❌ Runner configuration failed with exit code \$?"
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    log "✅ Runner configured successfully"
    
    # Stop existing service if running
    systemctl stop actions.runner.* 2>/dev/null || true
    
    # Install and start runner service
    cd $RUNNER_DIR
    ./svc.sh uninstall 2>/dev/null || true
    ./svc.sh install runner
    ./svc.sh start
    
    log "✅ GitHub Actions Runner configured and started as a service"
    
    # Verify service is running
    sleep 3
    if systemctl is-active --quiet actions.runner.* 2>/dev/null; then
        log "✅ Runner service is running"
        systemctl status actions.runner.* --no-pager
    else
        log "⚠️  WARNING: Runner service may not be running properly"
        ./svc.sh status
    fi
else
    log "❌ Failed to configure runner"
    exit 1
fi

log "✅ Runner setup complete!"
