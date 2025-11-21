#!/bin/bash
# Lightweight User-Data Script for Pre-Built AMI
# This script only configures the GitHub Actions Runner
# All packages (Docker, Nginx, AWS CLI, etc.) are pre-installed in the AMI

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
log "jq: $(jq --version 2>&1 || echo 'NOT FOUND')"
log "gh CLI: $(gh --version 2>&1 | head -1 || echo 'NOT FOUND')"

# Install jq if not present (required for runner config verification)
if ! command -v jq &> /dev/null; then
    log "Installing jq..."
    apt-get update -qq
    apt-get install -y jq -qq
    log "✅ jq installed"
fi

# Install gh CLI if not present (required for token generation)
if ! command -v gh &> /dev/null; then
    log "Installing GitHub CLI (gh)..."
    apt-get update -qq
    # Install gh CLI
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -qq
    apt-get install -y gh -qq
    log "✅ GitHub CLI installed: $(gh --version | head -1)"
fi

# Check if runner user exists
if id "runner" &>/dev/null; then
    log "✅ Runner user exists"
else
    log "❌ Runner user not found - creating..."
    useradd -m -s /bin/bash runner
    usermod -aG docker runner
fi

# Verify runner directory and ownership
RUNNER_DIR="/home/runner/actions-runner"
if [ -d "$${RUNNER_DIR}" ]; then
    log "✅ Runner directory exists: $${RUNNER_DIR}"
    log "Contents: $(ls -la $${RUNNER_DIR} | wc -l) files"
    
    # Ensure proper ownership
    chown -R runner:runner $${RUNNER_DIR}
    log "✅ Runner directory ownership verified"
    
    # Verify runner version
    if [ -f "$${RUNNER_DIR}/config.sh" ]; then
        RUNNER_VERSION=$(cd $${RUNNER_DIR} && sudo -u runner ./config.sh --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
        if [ "$${RUNNER_VERSION}" != "unknown" ]; then
            log "✅ Runner version: $${RUNNER_VERSION}"
            
            # Verify version is >= 2.310.0 (required for correct API endpoint)
            REQUIRED_VERSION="2.310.0"
            if [ "$(printf '%s\n' "$${REQUIRED_VERSION}" "$${RUNNER_VERSION}" | sort -V | head -n1)" = "$${REQUIRED_VERSION}" ]; then
                log "✅ Runner version is compatible (>= 2.310.0)"
            else
                log "⚠️  WARNING: Runner version $${RUNNER_VERSION} is older than recommended 2.310.0"
                log "⚠️  May cause registration issues with deprecated API endpoints"
            fi
        else
            log "⚠️  Could not determine runner version"
        fi
    fi
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

# Generate runner registration token using gh CLI (matches test script)
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
# NOTE: Execute directly as runner user without heredoc to avoid environment detection issues
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
    
    # Verify registration file with jq
    if [ -f "$${RUNNER_DIR}/.runner" ]; then
        log "✅ Runner registration file created:"
        if command -v jq &> /dev/null; then
            cat "$${RUNNER_DIR}/.runner" | jq '.'
        else
            cat "$${RUNNER_DIR}/.runner"
        fi
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

# Setup Nginx auto-configuration
log "======================================"
log "Setting up Nginx Auto-Configuration"
log "======================================"

# Create nginx config directory
mkdir -p /opt/nginx/conf.d

# Create auto-config script
cat > /opt/nginx/auto-config.sh <<'AUTOCONFIG'
#!/bin/bash
# Nginx auto-configuration for Docker containers

NGINX_CONF_DIR="/etc/nginx/conf.d"
TEMP_DIR="/opt/nginx/conf.d"

generate_config() {
    local container_name=$1
    local port=$2
    local host=$3
    local path=$4
    
    # Default path to container name if not specified
    path=$${path:-/$${container_name}}
    
    local config_file="$TEMP_DIR/$${container_name}.conf"
    
    cat > $config_file <<NGINXEOF
location $path {
    proxy_pass http://$container_name:$port;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
NGINXEOF
    
    # Copy to nginx and reload
    cp $config_file $NGINX_CONF_DIR/
    nginx -t && nginx -s reload
    
    echo "Generated config for $container_name at $path -> :$port"
}

remove_config() {
    local container_name=$1
    local config_file="$NGINX_CONF_DIR/$${container_name}.conf"
    
    if [ -f "$config_file" ]; then
        rm $config_file
        nginx -t && nginx -s reload
        echo "Removed config for $container_name"
    fi
}

# Monitor Docker events
docker events --filter 'type=container' --filter 'event=start' --filter 'event=stop' --format '{{.Status}}:{{.Actor.Attributes.name}}:{{.Actor.Attributes.nginx.port}}:{{.Actor.Attributes.nginx.host}}:{{.Actor.Attributes.nginx.path}}' | while IFS=: read -r status container_name port host path; do
    case $status in
        start)
            if [ -n "$port" ]; then
                generate_config $container_name $port $host $path
            fi
            ;;
        stop)
            remove_config $container_name
            ;;
    esac
done
AUTOCONFIG

chmod +x /opt/nginx/auto-config.sh

# Create systemd service for nginx auto-config
cat > /etc/systemd/system/nginx-auto-config.service <<'SYSTEMD'
[Unit]
Description=Nginx Auto Configuration Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
ExecStart=/opt/nginx/auto-config.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD

# Enable and start the service
systemctl daemon-reload
systemctl enable nginx-auto-config.service
systemctl start nginx-auto-config.service

if systemctl is-active --quiet nginx-auto-config.service; then
    log "✅ Nginx auto-config service started"
else
    log "⚠️  WARNING: Nginx auto-config service failed to start"
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
