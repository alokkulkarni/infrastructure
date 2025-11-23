#!/bin/bash
# Lightweight User-Data Script for Pre-Built AMI
# This script only configures the GitHub Actions Runner
# All packages (Docker, Nginx, AWS CLI, etc.) are pre-installed in the AMI
#
# TERRAFORM TEMPLATE ESCAPING:
# - Double dollar signs ($$) before braces to escape Terraform variables
# - Single dollar for bash command substitution with parentheses
# - Single dollar for regular bash variables
# - Double percent signs (%%) to escape percent characters

set -e
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

# Log function
log() {
    local msg="$${1}"
    local timestamp
    timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $msg"
}

log "======================================"
log "Starting GitHub Runner Configuration"
log "======================================"

# Runner configuration variables from Terraform
GITHUB_REPO_URL="${github_repo_url}"
GITHUB_PAT="${github_pat}"
RUNNER_NAME="${github_runner_name}"
RUNNER_LABELS="${github_runner_labels}"

log "Configuration:"
log "  Repository: $${GITHUB_REPO_URL}"
log "  Runner Name: $${RUNNER_NAME}"
log "  Runner Labels: $${RUNNER_LABELS}"
log "  PAT provided: $(if [ -n "$${GITHUB_PAT}" ] && [ "$${GITHUB_PAT}" != "" ]; then echo 'YES'; else echo 'NO'; fi)"

# Verify pre-installed packages
log "======================================"
log "Verifying Pre-Installed Packages"
log "======================================"

log "Docker: $(docker --version 2>&1 || echo 'NOT FOUND')"
log "Docker Compose: $(docker compose version 2>&1 || echo 'NOT FOUND')"
log "Nginx: $(nginx -v 2>&1 || echo 'NOT FOUND')"
log "AWS CLI: $(aws --version 2>&1 || echo 'NOT FOUND')"
log "Node.js: $(node --version 2>&1 || echo 'NOT FOUND')"
log "Python: $(python3 --version 2>&1 || echo 'NOT FOUND')"
log "Git: $(git --version 2>&1 || echo 'NOT FOUND')"

# Check if runner user exists
if id "runner" &>/dev/null; then
    log "✅ Runner user exists"
else
    log "❌ Runner user not found - creating..."
    useradd -m -s /bin/bash runner
    usermod -aG docker runner
fi

# Verify runner directory
RUNNER_DIR="/home/runner/actions-runner"
if [ -d "$${RUNNER_DIR}" ]; then
    log "✅ Runner directory exists: $${RUNNER_DIR}"
    log "Contents: $(ls -la $${RUNNER_DIR} | wc -l) files"
else
    log "❌ Runner directory not found - AMI may not be properly built"
    exit 1
fi

# Test GitHub connectivity
log "======================================"
log "Testing GitHub Connectivity"
log "======================================"

if timeout 10 curl -Is https://api.github.com --connect-timeout 10 > /dev/null 2>&1; then
    log "✅ GitHub API accessible"
else
    log "❌ Cannot reach GitHub API"
    log "Routes: $(ip route show)"
    log "Public IP: $(timeout 5 curl -s ifconfig.me || echo 'TIMEOUT')"
    log "WARNING: Proceeding with configuration anyway..."
fi

# Configure GitHub Actions Runner
log "======================================"
log "Configuring GitHub Actions Runner"
log "======================================"

if [ -z "$${GITHUB_PAT}" ] || [ "$${GITHUB_PAT}" == "" ]; then
    log "❌ ERROR: No GitHub PAT provided"
    log "Runner cannot be registered without a PAT"
    log "Please provide github_pat in terraform.tfvars"
    exit 1
fi

# Wait for NAT Gateway to be fully operational before attempting GitHub API calls
log "======================================"
log "Testing GitHub Connectivity"
log "======================================"

GITHUB_REACHABLE=false
MAX_RETRIES=30
RETRY_DELAY=10

for i in $(seq 1 $${MAX_RETRIES}); do
    log "Attempt $i/$${MAX_RETRIES}: Testing GitHub API connectivity..."
    if timeout 10 curl -s -o /dev/null -w "%%{http_code}" https://api.github.com | grep -q "200\|301\|302"; then
        log "✅ GitHub API is reachable"
        GITHUB_REACHABLE=true
        break
    else
        log "⚠️ GitHub API not reachable yet, waiting $${RETRY_DELAY}s..."
        if [ $i -lt $${MAX_RETRIES} ]; then
            sleep $${RETRY_DELAY}
        fi
    fi
done

if [ "$${GITHUB_REACHABLE}" = false ]; then
    log "❌ ERROR: GitHub API unreachable after $${MAX_RETRIES} attempts (5 minutes)"
    log "Routes: $(ip route)"
    log "DNS resolution test:"
    nslookup api.github.com || true
    log "This likely indicates NAT Gateway or routing issues"
    exit 1
fi

log "✅ Internet connectivity confirmed, proceeding with runner configuration"

# Authenticate gh CLI with PAT
log "Authenticating GitHub CLI with PAT..."
echo "$${GITHUB_PAT}" | gh auth login --with-token

if [ $? -eq 0 ]; then
    log "✅ GitHub CLI authenticated successfully"
    gh auth status
else
    log "❌ GitHub CLI authentication failed"
    exit 1
fi

# Extract owner and repo from URL
REPO_FULL=$(echo "$${GITHUB_REPO_URL}" | sed -E 's#https://github.com/([^/]+/[^/]+).*#\1#')
log "Extracted repository: $${REPO_FULL}"

# Generate runner registration token using gh CLI
log "Generating runner registration token via gh CLI..."
RUNNER_TOKEN=$(gh api --method POST "repos/$${REPO_FULL}/actions/runners/registration-token" --jq '.token' 2>&1)

if [ -z "$${RUNNER_TOKEN}" ] || [ "$${RUNNER_TOKEN}" == "" ]; then
    log "❌ ERROR: Failed to generate runner token"
    log "Token generation output: $${RUNNER_TOKEN}"
    exit 1
else
    log "✅ Runner token generated successfully"
    log "Token length: $${#RUNNER_TOKEN} characters"
fi

# Clear PAT from environment for security
unset GITHUB_PAT
log "✅ PAT cleared from environment"

# Check if runner is already configured
if [ -f "$${RUNNER_DIR}/.runner" ]; then
    log "⚠️  Runner already configured - removing previous configuration..."
    cd $${RUNNER_DIR}
    sudo -u runner ./config.sh remove --token "$${RUNNER_TOKEN}" || true
fi

# Configure runner as runner user
log "Configuring runner..."
cd $${RUNNER_DIR}

# Run config.sh with verbose output for debugging
sudo -u runner ./config.sh \
    --url "$${GITHUB_REPO_URL}" \
    --token "$${RUNNER_TOKEN}" \
    --name "$${RUNNER_NAME}" \
    --labels "$${RUNNER_LABELS}" \
    --unattended \
    --replace 2>&1 | tee -a /var/log/runner-config.log

CONFIG_EXIT_CODE=$${PIPESTATUS[0]}

if [ $${CONFIG_EXIT_CODE} -eq 0 ]; then
    log "✅ Runner configuration successful"
    
    # Verify registration file
    if [ -f "$${RUNNER_DIR}/.runner" ]; then
        log "✅ Runner registration file created:"
        cat "$${RUNNER_DIR}/.runner" 2>/dev/null || echo "Could not read .runner file"
    else
        log "⚠️  WARNING: .runner file not found after configuration"
    fi
    
    # Verify credentials file
    if [ -f "$${RUNNER_DIR}/.credentials" ]; then
        log "✅ Credentials file created"
    else
        log "⚠️  WARNING: .credentials file not found"
    fi
else
    log "❌ Runner configuration failed with exit code $${CONFIG_EXIT_CODE}"
    log "Configuration output saved to /var/log/runner-config.log"
    log "This usually indicates:"
    log "  1. Invalid or expired registration token"
    log "  2. Network connectivity issues"
    log "  3. Incorrect repository URL"
    log "  4. Runner version incompatibility"
    exit 1
fi

# Install and start runner service
log "======================================"
log "Starting Runner Service"
log "======================================"

cd $${RUNNER_DIR}
./svc.sh install runner
./svc.sh start

# Wait a moment for service to start
sleep 3

# Verify service is running
if systemctl is-active --quiet actions.runner.* 2>/dev/null || ./svc.sh status | grep -q "active"; then
    log "✅ Runner service is running"
    RUNNER_STATUS="ACTIVE"
else
    log "⚠️  WARNING: Runner service may not be running"
    RUNNER_STATUS="UNKNOWN"
    ./svc.sh status || true
fi

# Verify Nginx service is running
log "======================================"
log "Verifying Nginx Service"
log "======================================"

if systemctl is-active --quiet nginx; then
    log "✅ Native Nginx service is running"
    log "Nginx version: $(nginx -v 2>&1)"
else
    log "⚠️  Starting Nginx service..."
    systemctl start nginx
    if systemctl is-active --quiet nginx; then
        log "✅ Nginx started successfully"
    else
        log "❌ Failed to start Nginx"
        systemctl status nginx --no-pager
    fi
fi

# Verify nginx-auto-config service
log "======================================"
log "Verifying Nginx Auto-Configuration"
log "======================================"

if [ -f "/usr/local/bin/nginx-auto-config.sh" ]; then
    log "✅ Nginx auto-config script found"
    
    # Ensure service is enabled and running
    systemctl enable nginx-auto-config.service 2>/dev/null || log "Service already enabled"
    systemctl restart nginx-auto-config.service
    
    if systemctl is-active --quiet nginx-auto-config.service; then
        log "✅ Nginx auto-config service is running"
    else
        log "❌ Nginx auto-config service failed"
        systemctl status nginx-auto-config.service --no-pager
    fi
else
    log "⚠️  WARNING: Nginx auto-config script not found in AMI"
    log "Expected location: /usr/local/bin/nginx-auto-config.sh"
    log "Container configs will not be auto-generated"
fi

# Final status
log "======================================"
log "Configuration Complete"
log "======================================"
log "Runner Status: $${RUNNER_STATUS}"
log "Runner Name: $${RUNNER_NAME}"
log "Runner Labels: $${RUNNER_LABELS}"
log "Log File: /var/log/user-data.log"
log "Completed at: $(date)"
log "======================================"

# Write completion marker
echo "USER_DATA_COMPLETED_AT=$(date +%s)" > /var/log/user-data-complete.txt
