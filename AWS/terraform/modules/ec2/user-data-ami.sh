#!/bin/bash
# Lightweight User-Data Script for Pre-Built AMI
# This script only configures the GitHub Actions Runner
# All packages (Docker, Nginx, AWS CLI, etc.) are pre-installed in the AMI

set -e
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "======================================"
log "Starting GitHub Runner Configuration"
log "======================================"

# Runner configuration variables from Terraform
GITHUB_REPO_URL="${github_repo_url}"
RUNNER_TOKEN="${github_runner_token}"
RUNNER_NAME="${github_runner_name}"
RUNNER_LABELS="${github_runner_labels}"

log "Configuration:"
log "  Repository: $GITHUB_REPO_URL"
log "  Runner Name: $RUNNER_NAME"
log "  Runner Labels: $RUNNER_LABELS"
log "  Token provided: $(if [ -n "$RUNNER_TOKEN" ] && [ "$RUNNER_TOKEN" != "" ]; then echo 'YES'; else echo 'NO'; fi)"

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
if [ -d "$RUNNER_DIR" ]; then
    log "✅ Runner directory exists: $RUNNER_DIR"
    log "Contents: $(ls -la $RUNNER_DIR | wc -l) files"
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

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "" ]; then
    log "❌ ERROR: No runner token provided"
    log "Runner cannot be registered without a token"
    log "Please provide github_runner_token in terraform.tfvars"
    exit 1
fi

# Check if runner is already configured
if [ -f "$RUNNER_DIR/.runner" ]; then
    log "⚠️  Runner already configured - removing previous configuration..."
    cd $RUNNER_DIR
    sudo -u runner ./config.sh remove --token "$RUNNER_TOKEN" || true
fi

# Configure runner as runner user
log "Configuring runner..."
cd $RUNNER_DIR

sudo -u runner bash <<EOF
set -e
./config.sh \
    --url $GITHUB_REPO_URL \
    --token $RUNNER_TOKEN \
    --name $RUNNER_NAME \
    --labels $RUNNER_LABELS \
    --unattended \
    --replace

if [ \$? -eq 0 ]; then
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

if [ $? -ne 0 ]; then
    log "❌ Failed to configure runner"
    exit 1
fi

# Install and start runner service
log "======================================"
log "Starting Runner Service"
log "======================================"

cd $RUNNER_DIR
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
    path=${path:-/$container_name}
    
    local config_file="$TEMP_DIR/${container_name}.conf"
    
    cat > $config_file <<EOF
location $path {
    proxy_pass http://${container_name}:${port};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF
    
    # Copy to nginx and reload
    cp $config_file $NGINX_CONF_DIR/
    nginx -t && nginx -s reload
    
    echo "Generated config for $container_name at $path -> :$port"
}

remove_config() {
    local container_name=$1
    local config_file="$NGINX_CONF_DIR/${container_name}.conf"
    
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
log "Runner Status: $RUNNER_STATUS"
log "Runner Name: $RUNNER_NAME"
log "Runner Labels: $RUNNER_LABELS"
log "Log File: /var/log/user-data.log"
log "Completed at: $(date)"
log "======================================"

# Write completion marker
echo "USER_DATA_COMPLETED_AT=$(date +%s)" > /var/log/user-data-complete.txt
