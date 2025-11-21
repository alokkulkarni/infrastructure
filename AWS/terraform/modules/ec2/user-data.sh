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
apt-get install -y curl wget ca-certificates || log "⚠️  Some packages failed to install"

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
# Using 2.329.0 explicitly - DO NOT use "latest" as 2.330.0 has IsHostedServer detection bug
RUNNER_VERSION="2.329.0"
log "Runner version: $RUNNER_VERSION (using 2.329.0 due to 2.330.0 bug)"

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
RUNNER_TOKEN="${github_runner_token}"
RUNNER_NAME="${github_runner_name}"
RUNNER_LABELS="${github_runner_labels}"

log "Runner configuration:"
log "  Repository URL: $GITHUB_REPO_URL"
log "  Runner Name: $RUNNER_NAME"
log "  Runner Labels: $RUNNER_LABELS"
log "  Token provided: $(if [ -n "$RUNNER_TOKEN" ] && [ "$RUNNER_TOKEN" != "" ]; then echo 'YES'; else echo 'NO'; fi)"

# Configure and start runner if token is available
if [ -n "$RUNNER_TOKEN" ] && [ "$RUNNER_TOKEN" != "" ]; then
    log "Configuring runner with provided token..."
    
    # Configure runner as runner user
    su - runner -c "cd $RUNNER_DIR && ./config.sh --url $GITHUB_REPO_URL --token $RUNNER_TOKEN --name $RUNNER_NAME --labels $RUNNER_LABELS --unattended --replace"
    
    if [ $? -eq 0 ]; then
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
else
    log "❌ ERROR: No runner token provided. Runner will need to be configured manually."
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

# Install and configure Nginx as a Docker container
echo "Setting up Nginx as reverse proxy..."

# Create nginx configuration directory
mkdir -p /opt/nginx/conf.d
mkdir -p /opt/nginx/html

# Create dynamic Nginx configuration with Docker DNS
cat > /opt/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

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

    # Docker DNS resolver
    resolver 127.0.0.11 valid=30s;

    # Default server
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Default response
        location / {
            return 200 "Nginx reverse proxy is running. Configure your services in /opt/nginx/conf.d/\n";
            add_header Content-Type text/plain;
        }
    }

    # Include additional configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create example service configuration template
cat > /opt/nginx/conf.d/README.md <<'EOF'
# Nginx Service Configuration

This directory contains Nginx configuration files for routing to your Docker services.

## Example Configuration

To add a service, create a file like `myservice.conf`:

```nginx
# Route /api to a service named "api-service"
upstream api_backend {
    server api-service:8080;
}

server {
    listen 80;
    server_name api.example.com;  # or use default_server

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

1. **Service Names**: Use Docker container/service names as upstream servers
2. **Network**: Ensure your services are on the 'app-network' Docker network
3. **Reload**: After adding configurations, reload Nginx:
   ```
   docker exec nginx nginx -s reload
   ```
4. **Container Names**: Reference services by their container name or docker-compose service name

## Common Patterns

### Path-based routing:
```nginx
location /api/ {
    proxy_pass http://api-service:8080/;
}
location /web/ {
    proxy_pass http://web-service:3000/;
}
```

### Host-based routing:
```nginx
server {
    server_name api.example.com;
    location / {
        proxy_pass http://api-service:8080;
    }
}
```

### Load balancing:
```nginx
upstream app_cluster {
    server app1:8080;
    server app2:8080;
    server app3:8080;
}
```
EOF

# Create example service config (disabled by default)
cat > /opt/nginx/conf.d/example-service.conf.disabled <<'EOF'
# Example: Route requests to a service
# Rename this file to .conf to enable

upstream example_backend {
    # Use Docker service/container name
    server example-service:8080;
}

server {
    listen 80;
    # Remove default_server from the main nginx.conf if you want this to be default
    # server_name example.com www.example.com;

    location /app {
        proxy_pass http://example_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Create automated Nginx configuration management script
echo "Creating automated Nginx configuration manager..."
cat > /opt/nginx/auto-config.sh <<'AUTOCONFIG'
#!/bin/bash
# Automated Nginx Configuration Manager
# This script watches Docker events and automatically generates Nginx configurations

LOG_FILE="/var/log/nginx-auto-config.log"
CONFIG_DIR="/opt/nginx/conf.d"
GENERATED_DIR="$CONFIG_DIR/auto-generated"

# Create directory for auto-generated configs
mkdir -p $GENERATED_DIR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to extract service metadata from container labels
get_container_info() {
    local container_id=$1
    docker inspect $container_id --format '{{json .}}' 2>/dev/null
}

# Function to generate Nginx config for a container
generate_config() {
    local container_id=$1
    local container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/^\///')
    local network=$(docker inspect --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' $container_id)
    
    # Check if container is on app-network
    if [ "$network" != "app-network" ]; then
        log "Container $container_name is not on app-network, skipping"
        return
    fi
    
    # Get exposed port from container
    local port=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{end}}' $container_id | cut -d'/' -f1 | head -n1)
    
    # Get labels for configuration
    local nginx_enable=$(docker inspect --format='{{index .Config.Labels "nginx.enable"}}' $container_id)
    local nginx_host=$(docker inspect --format='{{index .Config.Labels "nginx.host"}}' $container_id)
    local nginx_path=$(docker inspect --format='{{index .Config.Labels "nginx.path"}}' $container_id)
    local nginx_port=$(docker inspect --format='{{index .Config.Labels "nginx.port"}}' $container_id)
    
    # Use label port or detected port
    if [ -n "$nginx_port" ] && [ "$nginx_port" != "<no value>" ]; then
        port=$nginx_port
    fi
    
    # Skip if nginx.enable is explicitly set to false
    if [ "$nginx_enable" == "false" ]; then
        log "Nginx disabled for $container_name via label"
        return
    fi
    
    # Default path if not specified
    if [ -z "$nginx_path" ] || [ "$nginx_path" == "<no value>" ]; then
        nginx_path="/$container_name"
    fi
    
    local config_file="$GENERATED_DIR/$${container_name}.conf"
    
    log "Generating Nginx config for container: $container_name (port: $port, path: $nginx_path)"
    
    # Generate configuration
    cat > $config_file <<NGINXCONF
# Auto-generated configuration for $container_name
# Generated at: $(date)
# Container ID: $container_id

upstream $${container_name}_backend {
    server $${container_name}:$${port};
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
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINXCONF
    
    log "Configuration created: $config_file"
    
    # Reload Nginx
    reload_nginx
}

# Function to remove Nginx config for a container
remove_config() {
    local container_name=$1
    local config_file="$GENERATED_DIR/$${container_name}.conf"
    
    if [ -f $config_file ]; then
        log "Removing Nginx config for container: $container_name"
        rm -f $config_file
        reload_nginx
    fi
}

# Function to reload Nginx
reload_nginx() {
    log "Reloading Nginx configuration..."
    
    # Test configuration first
    if docker exec nginx nginx -t 2>&1 | tee -a $LOG_FILE; then
        docker exec nginx nginx -s reload 2>&1 | tee -a $LOG_FILE
        log "Nginx reloaded successfully"
    else
        log "ERROR: Nginx configuration test failed!"
    fi
}

# Initialize - generate configs for existing containers
echo "Initializing: Scanning existing containers..."
docker ps --filter "network=app-network" --format '{{.ID}}' | while read container_id; do
    generate_config $container_id
done

# Watch Docker events
log "Starting Docker events monitor..."
docker events --filter 'type=container' --filter 'event=start' --filter 'event=die' --filter 'event=stop' --format '{{json .}}' | while read event; do
    event_type=$(echo $event | jq -r '.status')
    container_id=$(echo $event | jq -r '.id')
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    
    log "Docker event: $event_type for container $container_name ($container_id)"
    
    case $event_type in
        start)
            # Wait a moment for container to fully start
            sleep 2
            generate_config $container_id
            ;;
        die|stop)
            remove_config $container_name
            ;;
    esac
done
AUTOCONFIG

chmod +x /opt/nginx/auto-config.sh

# Create systemd service for the auto-config script
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
StandardOutput=append:/var/log/nginx-auto-config.log
StandardError=append:/var/log/nginx-auto-config.log

[Install]
WantedBy=multi-user.target
SYSTEMD

echo "Nginx automated configuration manager created"

# Run Nginx as a Docker container
echo "Starting Nginx container..."
docker run -d \
    --name nginx \
    --restart unless-stopped \
    --network app-network \
    -p 80:80 \
    -p 443:443 \
    -v /opt/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
    -v /opt/nginx/conf.d:/etc/nginx/conf.d:ro \
    -v /opt/nginx/html:/usr/share/nginx/html:ro \
    nginx:alpine

# Wait for Nginx to start
sleep 5

# Verify Nginx is running
if docker ps | grep -q nginx; then
    echo "Nginx container started successfully"
    docker logs nginx
else
    echo "Failed to start Nginx container"
    exit 1
fi

echo "Nginx reverse proxy setup completed"
echo "Configuration directory: /opt/nginx/conf.d/"
echo "Add your service configurations to /opt/nginx/conf.d/ and reload with: docker exec nginx nginx -s reload"

# Start Nginx auto-configuration service
echo "Starting Nginx auto-configuration service..."
systemctl daemon-reload
systemctl enable nginx-auto-config.service
systemctl start nginx-auto-config.service

# Verify service is running
if systemctl is-active --quiet nginx-auto-config.service; then
    echo "Nginx auto-configuration service started successfully"
    echo "The service will automatically create Nginx configs for containers with labels:"
    echo "  - nginx.enable=true (default if not specified)"
    echo "  - nginx.host=example.com (optional)"
    echo "  - nginx.path=/myapp (optional, defaults to /container-name)"
    echo "  - nginx.port=8080 (optional, auto-detected if not specified)"
else
    echo "WARNING: Nginx auto-configuration service failed to start"
    systemctl status nginx-auto-config.service
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
