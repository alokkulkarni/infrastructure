#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

# Define log function for script logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

echo "======================================"
echo "Starting EC2 Instance Setup"
echo "======================================"
echo "Timestamp: $(date)"

# Disable IPv6 to prevent apt from trying IPv6 connections through NAT Gateway
log "Disabling IPv6 for package installation..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Configure multiple Ubuntu mirrors for reliability
log "Configuring Ubuntu package mirrors with fallback options..."
cat > /etc/apt/sources.list <<'APT_SOURCES'
# Primary: AWS EC2 regional mirror (fastest)
deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse

# Fallback 1: Main Ubuntu archive
# deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse

# Fallback 2: CloudFront CDN mirror
# deb http://us.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb http://us.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
APT_SOURCES

# Configure apt to retry with timeout and use IPv4 only
log "Configuring apt for better reliability..."
cat > /etc/apt/apt.conf.d/99custom <<'APT_CONFIG'
Acquire::ForceIPv4 "true";
Acquire::http::Timeout "30";
Acquire::Retries "3";
Acquire::http::No-Cache "true";
APT_CONFIG

# Try to update package lists with retries
log "Updating package lists (with automatic fallback to mirrors)..."
retry_count=0
max_retries=3
until apt-get update -y || [ $retry_count -eq $max_retries ]; do
    retry_count=$((retry_count + 1))
    log "Package update attempt $retry_count failed, trying fallback mirror..."
    
    if [ $retry_count -eq 2 ]; then
        # Switch to main Ubuntu archive
        sed -i 's|eu-west-2.ec2.archive.ubuntu.com|archive.ubuntu.com|g' /etc/apt/sources.list
    elif [ $retry_count -eq 3 ]; then
        # Switch to US mirror
        sed -i 's|archive.ubuntu.com|us.archive.ubuntu.com|g' /etc/apt/sources.list
    fi
    sleep 5
done

if [ $retry_count -eq $max_retries ]; then
    log "⚠️  WARNING: Package update failed after $max_retries attempts. Will try to continue..."
fi

log "Upgrading existing packages..."
apt-get upgrade -y || log "⚠️  Package upgrade had issues, continuing..."

# Install minimal essential packages first (needed for runner setup)
log "Installing minimal essential packages for runner..."
apt-get install -y curl wget ca-certificates jq || log "⚠️  Some packages failed to install"

# Install GitHub CLI (gh) - needed for token generation
log "Installing GitHub CLI (gh)..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update -qq
apt-get install -y gh || log "⚠️  GitHub CLI installation had issues"
log "✅ GitHub CLI installed: $(gh --version | head -1)"

# ==============================================
# PRIORITY: Configure GitHub Actions Runner FIRST
# (before heavy Docker/Nginx installation)
# ==============================================
log "======================================"
log "Setting up GitHub Actions Runner (Priority 1)"
log "======================================"

# Create runner user
log "Creating runner user..."
useradd -m -s /bin/bash runner || log "Runner user may already exist"

# Install GitHub Actions Runner
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p $RUNNER_DIR
cd $RUNNER_DIR

# Download the latest runner package
log "Downloading GitHub Actions Runner..."
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
log "Runner version: $RUNNER_VERSION"

curl -o actions-runner-linux-x64-$RUNNER_VERSION.tar.gz -L \
  https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz || {
    log "❌ Failed to download runner package"
    exit 1
}

# Extract the installer
tar xzf ./actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
rm actions-runner-linux-x64-$RUNNER_VERSION.tar.gz

# Set ownership
chown -R runner:runner $RUNNER_DIR

# Runner configuration variables
GITHUB_REPO_URL="${github_repo_url}"
GITHUB_PAT="${github_pat}"
RUNNER_NAME="${github_runner_name}"
RUNNER_LABELS="${github_runner_labels}"

log "Runner configuration:"
log "  Repository URL: $GITHUB_REPO_URL"
log "  Runner Name: $RUNNER_NAME"
log "  Runner Labels: $RUNNER_LABELS"
log "  PAT provided: $(if [ -n "$GITHUB_PAT" ] && [ "$GITHUB_PAT" != "" ]; then echo 'YES'; else echo 'NO'; fi)"

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

# Configure and start runner using PAT + gh CLI approach
if [ -n "$GITHUB_PAT" ] && [ "$GITHUB_PAT" != "" ]; then
    log "Authenticating GitHub CLI with PAT..."
    echo "$GITHUB_PAT" | gh auth login --with-token
    
    if [ $? -eq 0 ]; then
        log "✅ GitHub CLI authenticated successfully"
        gh auth status
        
        # Extract owner and repo from URL
        REPO_FULL=$(echo "$GITHUB_REPO_URL" | sed -E 's#https://github.com/([^/]+/[^/]+).*#\1#')
        log "Extracted repository: $REPO_FULL"
        
        # Generate runner registration token using gh CLI (matches test script)
        log "Generating runner registration token via gh CLI..."
        RUNNER_TOKEN=$(gh api --method POST "repos/$REPO_FULL/actions/runners/registration-token" --jq '.token' 2>&1)
        
        if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "" ]; then
            log "❌ ERROR: Failed to generate runner token"
            log "Token generation output: $RUNNER_TOKEN"
        else
            log "✅ Runner token generated successfully"
            log "Token length: $${#RUNNER_TOKEN} characters"
            
            # Clear PAT from environment for security
            unset GITHUB_PAT
            log "✅ PAT cleared from environment"
            
            # Configure runner as runner user (direct execution, matches test script)
            log "Configuring runner with generated token..."
            cd $RUNNER_DIR
            sudo -u runner ./config.sh \
                --url "$GITHUB_REPO_URL" \
                --token "$RUNNER_TOKEN" \
                --name "$RUNNER_NAME" \
                --labels "$RUNNER_LABELS" \
                --unattended \
                --replace 2>&1 | tee -a /var/log/runner-config.log
            
            CONFIG_EXIT_CODE=$${PIPESTATUS[0]}
            
            if [ $CONFIG_EXIT_CODE -eq 0 ]; then
                log "✅ Runner configured successfully"
                
                # Install and start runner service
                cd $RUNNER_DIR
                ./svc.sh install runner
                ./svc.sh start
                
                log "✅ Runner service started"
                log "======================================"
                log "GitHub Actions Runner Setup Complete!"
                log "======================================"
            else
                log "❌ Runner configuration failed"
            fi
        fi
    else
        log "❌ GitHub CLI authentication failed"
    fi
else
    log "❌ ERROR: No GitHub PAT provided. Runner will need to be configured manually."
    log "To configure manually, run as the runner user:"
    log "sudo su - runner"
    log "cd $RUNNER_DIR"
    log "./config.sh --url $GITHUB_REPO_URL --token <YOUR_TOKEN> --name $RUNNER_NAME --labels $RUNNER_LABELS"
fi

# ==============================================
# NOW Install Docker and other services
# ==============================================
log "======================================"
log "Installing Docker and Additional Services"
log "======================================"

# Install remaining essential packages
log "Installing additional essential packages..."
apt-get install -y \
    git \
    jq \
    unzip \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common || log "⚠️  Some additional packages failed"

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y || log "⚠️  Docker repo update had issues"
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log "⚠️  Docker installation had issues"

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Verify Docker installation
docker --version
docker compose version

echo "Docker installation completed successfully"

# Create Docker network for services
echo "Creating Docker network for services..."
docker network create --driver bridge app-network

echo "Docker network 'app-network' created successfully"

# Install and configure Native Nginx (NOT Docker container)
log "====================================="
log "Installing Native Nginx"
log "====================================="

# Install Nginx
log "Installing nginx package..."
apt-get install -y nginx

# Create nginx configuration directories
log "Creating nginx configuration directories..."
mkdir -p /etc/nginx/conf.d/auto-generated
mkdir -p /var/log/nginx

# Create main Nginx configuration
log "Creating main nginx configuration..."
cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;

    # Default server
    server {
        listen 80 default_server;
        server_name _;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "Nginx reverse proxy is running\n";
            add_header Content-Type text/plain;
        }

        # Default response
        location / {
            return 200 "Nginx is running. Application routes will be auto-configured.\n";
            add_header Content-Type text/plain;
        }
    }

    # Include auto-generated configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/conf.d/auto-generated/*.conf;
}
EOF

# Create example service configuration template
cat > /etc/nginx/conf.d/README.md <<'EOF'
# Nginx Service Configuration

This directory contains Nginx configuration files for routing to your Docker services.
Auto-generated configurations are placed in /etc/nginx/conf.d/auto-generated/

## Example Configuration

To add a service manually, create a file like `myservice.conf`:

```nginx
# Route /api to a container by IP
upstream api_backend {
    server 172.18.0.5:8080;  # Use container IP from app-network
}

server {
    listen 80;
    server_name api.example.com;  # or omit for path-based routing

    location /api {
        proxy_pass http://api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## Important Notes

1. **Container IPs**: Use container IPs from app-network (native nginx cannot resolve Docker DNS)
2. **Network**: Ensure your services are on the 'app-network' Docker network
3. **Reload**: After adding configurations, reload Nginx:
   ```
   sudo nginx -t && sudo nginx -s reload
   ```
4. **Auto-Config**: The nginx-auto-config service automatically generates configs for labeled containers

EOF

# Create automated Nginx configuration management script
log "Creating automated Nginx configuration manager..."
cat > /usr/local/bin/nginx-auto-config.sh <<'AUTOCONFIG'
#!/bin/bash
# Nginx Auto-Configuration for Docker Containers
# Watches Docker events and generates Nginx configs using container IPs

LOG_FILE="/var/log/nginx-auto-config.log"
CONFIG_DIR="/etc/nginx/conf.d/auto-generated"

mkdir -p $CONFIG_DIR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

generate_config() {
    local container_id=$1
    local container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/^\///')
    
    # Get container IP from app-network
    local container_ip=$(docker inspect --format='{{.NetworkSettings.Networks.app-network.IPAddress}}' $container_id 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "Container $container_name not on app-network, skipping"
        return
    fi
    
    # Get labels
    local nginx_enable=$(docker inspect --format='{{index .Config.Labels "nginx.enable"}}' $container_id)
    local nginx_path=$(docker inspect --format='{{index .Config.Labels "nginx.path"}}' $container_id)
    local nginx_port=$(docker inspect --format='{{index .Config.Labels "nginx.port"}}' $container_id)
    local nginx_host=$(docker inspect --format='{{index .Config.Labels "nginx.host"}}' $container_id)
    
    # Skip if disabled
    if [ "$nginx_enable" == "false" ]; then
        log "Container $container_name has nginx.enable=false, skipping"
        return
    fi
    
    # Require nginx.path label
    if [ -z "$nginx_path" ] || [ "$nginx_path" == "<no value>" ]; then
        log "No nginx.path label for $container_name, skipping"
        return
    fi
    
    # Get internal container port (not host port)
    if [ -z "$nginx_port" ] || [ "$nginx_port" == "<no value>" ]; then
        # Auto-detect internal port from exposed ports
        nginx_port=$(docker inspect --format='{{range $key, $value := .Config.ExposedPorts}}{{$key}}{{end}}' $container_id | cut -d'/' -f1 | head -n1)
    fi
    
    if [ -z "$nginx_port" ]; then
        log "Could not determine port for $container_name, skipping"
        return
    fi
    
    local config_file="$CONFIG_DIR/$${container_name}.conf"
    
    log "Generating config for $container_name"
    log "  Container IP: $container_ip"
    log "  Container Port: $nginx_port"
    log "  Path: $nginx_path"
    
    # Generate Nginx config
    cat > $config_file <<NGINXCONF
# Auto-generated for $container_name
# Generated: $(date)
# Container IP: $container_ip

upstream $${container_name}_backend {
    server $${container_ip}:$${nginx_port};
}

server {
    listen 80;
NGINXCONF

    # Add server_name if specified
    if [ -n "$nginx_host" ] && [ "$nginx_host" != "<no value>" ]; then
        echo "    server_name $nginx_host;" >> $config_file
    fi
    
    cat >> $config_file <<NGINXCONF
    
    location $nginx_path {
        proxy_pass http://$${container_name}_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINXCONF
    
    # Test and reload
    if nginx -t 2>&1 | tee -a $LOG_FILE; then
        nginx -s reload 2>&1 | tee -a $LOG_FILE
        log "✅ Config created and loaded: $config_file"
    else
        log "❌ Nginx config test failed!"
        rm -f $config_file
    fi
}

remove_config() {
    local container_name=$1
    local config_file="$CONFIG_DIR/$${container_name}.conf"
    
    if [ -f $config_file ]; then
        log "Removing config for $container_name"
        rm -f $config_file
        nginx -t && nginx -s reload
    fi
}

# Initialize with existing containers
log "Initializing: scanning existing containers on app-network..."
docker ps --filter "network=app-network" --format '{{.ID}}' | while read cid; do
    generate_config $cid
done

# Monitor Docker events
log "Monitoring Docker events..."
docker events --filter 'type=container' --filter 'event=start' --filter 'event=die' --format '{{json .}}' | while read event; do
    event_type=$(echo $event | jq -r '.status')
    container_id=$(echo $event | jq -r '.id')
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    
    log "Event: $event_type for $container_name"
    
    case $event_type in
        start)
            sleep 2
            generate_config $container_id
            ;;
        die)
            remove_config $container_name
            ;;
    esac
done
AUTOCONFIG

chmod +x /usr/local/bin/nginx-auto-config.sh

# Create systemd service for nginx auto-config
log "Creating nginx-auto-config systemd service..."
cat > /etc/systemd/system/nginx-auto-config.service <<'SYSTEMD'
[Unit]
Description=Nginx Auto Configuration Manager
After=docker.service nginx.service
Requires=docker.service nginx.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/nginx-auto-config.sh
Restart=always
RestartSec=10
StandardOutput=append:/var/log/nginx-auto-config.log
StandardError=append:/var/log/nginx-auto-config.log

[Install]
WantedBy=multi-user.target
SYSTEMD

# Enable and start Nginx
log "Starting native Nginx service..."
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# Wait for Nginx to start
sleep 3

# Verify Nginx is running
if systemctl is-active --quiet nginx; then
    log "✅ Native Nginx service started successfully"
    log "Nginx version: $(nginx -v 2>&1)"
else
    log "❌ Failed to start Nginx service"
    systemctl status nginx --no-pager
    exit 1
fi

log "Testing Nginx configuration..."
if nginx -t; then
    log "✅ Nginx configuration test passed"
else
    log "❌ Nginx configuration test failed"
    exit 1
fi

log "Native Nginx setup completed"
log "Configuration directory: /etc/nginx/conf.d/"
log "Auto-generated configs: /etc/nginx/conf.d/auto-generated/"

# Start Nginx auto-configuration service
log "Starting Nginx auto-configuration service..."
systemctl enable nginx-auto-config.service
systemctl start nginx-auto-config.service

# Verify service is running
if systemctl is-active --quiet nginx-auto-config.service; then
    log "✅ Nginx auto-configuration service started successfully"
    log "The service will automatically create Nginx configs for containers with labels:"
    log "  - nginx.enable=true (required, or omit to auto-enable)"
    log "  - nginx.path=/myapp (required)"
    log "  - nginx.port=8080 (optional, auto-detected from exposed ports)"
    log "  - nginx.host=example.com (optional, for host-based routing)"
else
    log "⚠️  WARNING: Nginx auto-configuration service failed to start"
    systemctl status nginx-auto-config.service --no-pager
fi

# Install AWS CLI
log "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip
aws --version
log "AWS CLI installation completed"

# Install additional tools
echo "Installing additional tools..."

# Install Node.js (useful for many GitHub Actions)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Python and pip
apt-get install -y python3 python3-pip

# Install build essentials
apt-get install -y build-essential

echo "Additional tools installation completed"

# Set up log rotation for Docker
cat > /etc/logrotate.d/docker <<EOF
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  size=10M
  missingok
  delaycompress
  copytruncate
}
EOF

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

# Print system information
echo "======================================"
echo "Setup completed successfully!"
echo "======================================"
echo "System Information:"
echo "- Docker version: $(docker --version)"
echo "- Docker Compose version: $(docker compose version)"
echo "- Nginx version: $(nginx -v 2>&1)"
echo "- AWS CLI version: $(aws --version)"
echo "- Node.js version: $(node --version)"
echo "- Python version: $(python3 --version)"
echo ""
echo "GitHub Actions Runner:"
echo "- Runner directory: $RUNNER_DIR"
echo "- Runner name: $RUNNER_NAME"
echo "- Runner labels: $RUNNER_LABELS"
echo ""
echo "Log file: /var/log/user-data.log"
echo "======================================"
echo "Timestamp: $(date)"
