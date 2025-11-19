#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "======================================"
echo "Starting EC2 Instance Setup"
echo "======================================"
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install essential packages
echo "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

# Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Verify AWS CLI installation
aws --version

echo "AWS CLI installation completed"

# Setup GitHub Actions Runner
echo "Setting up GitHub Actions Runner..."

# Create a runner user
useradd -m -s /bin/bash runner
usermod -aG docker runner

# Create runner directory
RUNNER_HOME="/home/runner"
RUNNER_DIR="$RUNNER_HOME/actions-runner"
mkdir -p $RUNNER_DIR
cd $RUNNER_DIR

# Download the latest runner package
echo "Downloading GitHub Actions Runner..."
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
curl -o actions-runner-linux-x64-$RUNNER_VERSION.tar.gz -L \
  https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz

# Extract the installer
tar xzf ./actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
rm actions-runner-linux-x64-$RUNNER_VERSION.tar.gz

# Set ownership
chown -R runner:runner $RUNNER_DIR

# Configure runner
echo "Configuring GitHub Actions Runner..."

# Runner configuration variables
GITHUB_REPO_URL="${github_repo_url}"
RUNNER_TOKEN="${github_runner_token}"
RUNNER_NAME="${github_runner_name}"
RUNNER_LABELS="${github_runner_labels}"

# If token is not provided via Terraform, try to generate it
if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "" ]; then
    echo "No runner token provided. Runner will need to be configured manually."
    echo "To configure manually, run as the runner user:"
    echo "sudo su - runner"
    echo "cd $RUNNER_DIR"
    echo "./config.sh --url $GITHUB_REPO_URL --token YOUR_TOKEN --name $RUNNER_NAME --labels $RUNNER_LABELS"
else
    # Configure runner as runner user
    sudo -u runner bash <<EOF
cd $RUNNER_DIR
./config.sh \
    --url $GITHUB_REPO_URL \
    --token $RUNNER_TOKEN \
    --name $RUNNER_NAME \
    --labels $RUNNER_LABELS \
    --unattended \
    --replace
EOF

    # Install runner as a service
    cd $RUNNER_DIR
    ./svc.sh install runner
    ./svc.sh start

    echo "GitHub Actions Runner configured and started as a service"
fi

# Create a systemd service for the runner (alternative to svc.sh)
cat > /etc/systemd/system/github-runner.service <<EOF
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=runner
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service (backup method)
systemctl daemon-reload
# systemctl enable github-runner
# systemctl start github-runner

echo "GitHub Actions Runner setup completed"

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
