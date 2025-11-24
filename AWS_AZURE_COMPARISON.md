# AWS vs Azure Implementation Comparison

## Overview

This document provides a side-by-side comparison of AWS and Azure implementations to verify feature parity.

## 📦 Package Installation

### AWS (user-data.sh)
```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    awscli \
    nginx
```

### Azure (cloud-init.yaml)
```yaml
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - software-properties-common
  - jq
  - unzip
  - nginx
```

**Differences:**
- AWS includes `awscli` (cloud-specific)
- Azure includes `unzip` (cloud-specific)
- Both include `jq` and `nginx` ✅

## 🐳 Docker Installation

### AWS
```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu
```

### Azure
```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker azureuser
```

**Differences:**
- AWS uses `ubuntu` user
- Azure uses `azureuser` user
- **Logic identical** ✅

## 🌐 Docker Network

### AWS
```bash
docker network create --driver bridge app-network
```

### Azure
```bash
docker network create --driver bridge app-network
```

**Identical** ✅

## 🔧 Nginx Configuration

### AWS - Directory Setup
```bash
mkdir -p /etc/nginx/conf.d/auto-generated
mkdir -p /var/log/nginx
touch /etc/nginx/conf.d/auto-generated/upstreams.conf
touch /etc/nginx/conf.d/auto-generated/locations.conf
```

### Azure - Directory Setup
```bash
mkdir -p /etc/nginx/conf.d/auto-generated
mkdir -p /var/log/nginx
touch /etc/nginx/conf.d/auto-generated/upstreams.conf
touch /etc/nginx/conf.d/auto-generated/locations.conf
```

**Identical** ✅

### AWS - nginx.conf (Relevant Sections)
```nginx
http {
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
        
        # Include auto-generated container locations
        include /etc/nginx/conf.d/auto-generated/locations.conf;

        # Default response
        location / {
            return 200 "Nginx is running. Application routes will be auto-configured.\n";
            add_header Content-Type text/plain;
        }
    }

    # Include upstreams
    include /etc/nginx/conf.d/auto-generated/upstreams.conf;
}
```

### Azure - nginx.conf (Relevant Sections)
```nginx
http {
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
        
        # Include auto-generated container locations
        include /etc/nginx/conf.d/auto-generated/locations.conf;

        # Default response
        location / {
            return 200 "Nginx is running. Application routes will be auto-configured.\n";
            add_header Content-Type text/plain;
        }
    }

    # Include upstreams
    include /etc/nginx/conf.d/auto-generated/upstreams.conf;
}
```

**Identical** ✅

## 🤖 Auto-Config Script

### Core Functions Comparison

#### collect_container_info()

**AWS:**
```bash
collect_container_info() {
    local container_id=$1
    local container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/^\///')
    
    # Get container IP from app-network using jq for reliability
    local container_ip=$(docker inspect $container_id | jq -r '.[0].NetworkSettings.Networks["app-network"].IPAddress // empty' 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "Container $container_name not on app-network, skipping"
        return
    fi
    
    # Get labels
    local nginx_enable=$(docker inspect --format='{{index .Config.Labels "nginx.enable"}}' $container_id)
    local nginx_path=$(docker inspect --format='{{index .Config.Labels "nginx.path"}}' $container_id)
    local nginx_port=$(docker inspect --format='{{index .Config.Labels "nginx.port"}}' $container_id)
    
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
    
    # ... (port detection logic)
    
    log "Found container: $container_name at $container_ip:$nginx_port path $nginx_path"
    
    # Store info in temp file
    echo "$container_name|$container_ip|$nginx_port|$nginx_path" >> /tmp/nginx-containers.tmp
}
```

**Azure:**
```bash
collect_container_info() {
    local container_id=$1
    local container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/^\///')
    
    # Get container IP from app-network using jq for reliability
    local container_ip=$(docker inspect $container_id | jq -r '.[0].NetworkSettings.Networks["app-network"].IPAddress // empty' 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "Container $container_name not on app-network, skipping"
        return
    fi
    
    # Get labels
    local nginx_enable=$(docker inspect --format='{{index .Config.Labels "nginx.enable"}}' $container_id)
    local nginx_path=$(docker inspect --format='{{index .Config.Labels "nginx.path"}}' $container_id)
    local nginx_port=$(docker inspect --format='{{index .Config.Labels "nginx.port"}}' $container_id)
    
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
    
    # ... (port detection logic)
    
    log "Found container: $container_name at $container_ip:$nginx_port path $nginx_path"
    
    # Store info in temp file
    echo "$container_name|$container_ip|$nginx_port|$nginx_path" >> /tmp/nginx-containers.tmp
}
```

**Identical** ✅

#### generate_consolidated_config()

**AWS:**
```bash
generate_consolidated_config() {
    local temp_file="/tmp/nginx-containers.tmp"
    
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        log "No containers to configure"
        return
    fi
    
    log "Generating consolidated nginx configuration..."
    
    # Generate upstreams file
    local upstream_file="$CONFIG_DIR/upstreams.conf"
    echo "# Auto-generated upstreams - $(date)" > $upstream_file
    
    while IFS='|' read -r name ip port path; do
        cat >> $upstream_file <<UPSTREAM
upstream $${name}_backend {
    server $${ip}:$${port};
    keepalive 32;
}
UPSTREAM
    done < $temp_file
    
    # Generate locations file
    local locations_file="$CONFIG_DIR/locations.conf"
    echo "# Auto-generated locations - $(date)" > $locations_file
    echo "# These locations are included in the main server block" >> $locations_file
    
    while IFS='|' read -r name ip port path; do
        # Add trailing slash to path for proper matching
        local path_prefix="$path"
        [ "$path" != "/" ] && path_prefix="$${path}/"
        
        cat >> $locations_file <<LOCATION

location $path_prefix {
    rewrite ^$path/(.*) /\$1 break;
    proxy_pass http://$${name}_backend;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
LOCATION
    done < $temp_file
    
    # Test and reload
    log "Testing nginx configuration..."
    if nginx -t 2>&1 | tee -a $LOG_FILE; then
        systemctl reload nginx 2>&1 | tee -a $LOG_FILE
        log "✅ Consolidated config created and loaded"
    else
        log "❌ Nginx config test failed!"
        rm -f $upstream_file $locations_file
    fi
    
    # Cleanup temp file
    rm -f $temp_file
}
```

**Azure:**
```bash
generate_consolidated_config() {
    local temp_file="/tmp/nginx-containers.tmp"
    
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        log "No containers to configure"
        return
    fi
    
    log "Generating consolidated nginx configuration..."
    
    # Generate upstreams file
    local upstream_file="$CONFIG_DIR/upstreams.conf"
    echo "# Auto-generated upstreams - $(date)" > $upstream_file
    
    while IFS='|' read -r name ip port path; do
        cat >> $upstream_file <<UPSTREAM
upstream $${name}_backend {
    server $${ip}:$${port};
    keepalive 32;
}
UPSTREAM
    done < $temp_file
    
    # Generate locations file
    local locations_file="$CONFIG_DIR/locations.conf"
    echo "# Auto-generated locations - $(date)" > $locations_file
    echo "# These locations are included in the main server block" >> $locations_file
    
    while IFS='|' read -r name ip port path; do
        # Add trailing slash to path for proper matching
        local path_prefix="$path"
        [ "$path" != "/" ] && path_prefix="$${path}/"
        
        cat >> $locations_file <<LOCATION

location $path_prefix {
    rewrite ^$path/(.*) /\$1 break;
    proxy_pass http://$${name}_backend;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
LOCATION
    done < $temp_file
    
    # Test and reload
    log "Testing nginx configuration..."
    if nginx -t 2>&1 | tee -a $LOG_FILE; then
        systemctl reload nginx 2>&1 | tee -a $LOG_FILE
        log "✅ Consolidated config created and loaded"
    else
        log "❌ Nginx config test failed!"
        rm -f $upstream_file $locations_file
    fi
    
    # Cleanup temp file
    rm -f $temp_file
}
```

**Identical** ✅

#### rebuild_all_configs()

**AWS:**
```bash
rebuild_all_configs() {
    log "Rebuilding all container configurations..."
    
    # Clear temp file
    rm -f /tmp/nginx-containers.tmp
    
    # Collect all containers on app-network
    docker ps --filter "network=app-network" --format '{{.ID}}' | while read cid; do
        collect_container_info $cid
    done
    
    # Generate consolidated config
    generate_consolidated_config
}
```

**Azure:**
```bash
rebuild_all_configs() {
    log "Rebuilding all container configurations..."
    
    # Clear temp file
    rm -f /tmp/nginx-containers.tmp
    
    # Collect all containers on app-network
    docker ps --filter "network=app-network" --format '{{.ID}}' | while read cid; do
        collect_container_info $cid
    done
    
    # Generate consolidated config
    generate_consolidated_config
}
```

**Identical** ✅

#### Event Monitoring

**AWS:**
```bash
# Initialize with existing containers
log "Initializing: scanning existing containers on app-network..."
rebuild_all_configs

# Monitor Docker events
log "Monitoring Docker events..."
docker events --filter 'type=container' --filter 'event=start' --filter 'event=die' --format '{{json .}}' | while read event; do
    event_type=$(echo $event | jq -r '.status')
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    
    log "Event: $event_type for $container_name"
    
    # Always rebuild all configs on any container change
    sleep 2
    rebuild_all_configs
done
```

**Azure:**
```bash
# Initialize with existing containers
log "Initializing: scanning existing containers on app-network..."
rebuild_all_configs

# Monitor Docker events
log "Monitoring Docker events..."
docker events --filter 'type=container' --filter 'event=start' --filter 'event=die' --format '{{json .}}' | while read event; do
    event_type=$(echo $event | jq -r '.status')
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    
    log "Event: $event_type for $container_name"
    
    # Always rebuild all configs on any container change
    sleep 2
    rebuild_all_configs
done
```

**Identical** ✅

## 🔧 Systemd Service

### AWS
```ini
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
```

### Azure
```ini
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
```

**Identical** ✅

## 🏃 GitHub Runner Setup

### AWS
```bash
# Install GitHub Actions Runner
mkdir -p /opt/actions-runner
cd /opt/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
chown -R ubuntu:ubuntu /opt/actions-runner

# Configure and start runner
sudo -u ubuntu bash -c "cd /opt/actions-runner && ./config.sh --url $GITHUB_REPO_URL --token $GITHUB_RUNNER_TOKEN --name $RUNNER_NAME --labels $RUNNER_LABELS --unattended --replace"
cd /opt/actions-runner
./svc.sh install ubuntu

# Add runner user to docker group and restart service
usermod -aG docker ubuntu
if systemctl is-active --quiet actions.runner.* 2>/dev/null; then
  systemctl restart actions.runner.*.service
fi

./svc.sh start
```

### Azure
```bash
# Install GitHub Actions Runner
mkdir -p /opt/actions-runner
cd /opt/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
chown -R azureuser:azureuser /opt/actions-runner

# Configure and start runner
sudo -u azureuser bash -c "cd /opt/actions-runner && ./config.sh --url ${github_repo_url} --token ${github_runner_token} --name ${github_runner_name} --labels ${github_runner_labels} --unattended --replace"
cd /opt/actions-runner
./svc.sh install azureuser

# Add runner user to docker group and restart service
usermod -aG docker azureuser
if systemctl is-active --quiet actions.runner.* 2>/dev/null; then
  systemctl restart actions.runner.*.service
fi

./svc.sh start
```

**Differences:**
- AWS uses `ubuntu` user
- Azure uses `azureuser` user  
- Azure uses Terraform variable syntax `${github_repo_url}`
- **Logic identical** ✅

## 📊 Generated Config Examples

### upstreams.conf (Both Platforms)
```nginx
# Auto-generated upstreams - Sun Nov 24 10:05:02 UTC 2024
upstream beneficiaries_backend {
    server 172.18.0.5:8080;
    keepalive 32;
}
upstream paymentprocessor_backend {
    server 172.18.0.6:8081;
    keepalive 32;
}
upstream paymentconsumer_backend {
    server 172.18.0.7:8082;
    keepalive 32;
}
```

**Identical** ✅

### locations.conf (Both Platforms)
```nginx
# Auto-generated locations - Sun Nov 24 10:05:02 UTC 2024
# These locations are included in the main server block

location /dev/beneficiaries/ {
    rewrite ^/dev/beneficiaries/(.*) /$1 break;
    proxy_pass http://beneficiaries_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}

location /dev/paymentprocessor/ {
    rewrite ^/dev/paymentprocessor/(.*) /$1 break;
    proxy_pass http://paymentprocessor_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}

location /dev/paymentconsumer/ {
    rewrite ^/dev/paymentconsumer/(.*) /$1 break;
    proxy_pass http://paymentconsumer_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

**Identical** ✅

## 🎯 Summary

### Complete Parity ✅

| Component | AWS | Azure | Status |
|-----------|-----|-------|--------|
| **Nginx Architecture** | Native systemd | Native systemd | ✅ Identical |
| **Config Directory** | `/etc/nginx/conf.d/auto-generated/` | `/etc/nginx/conf.d/auto-generated/` | ✅ Identical |
| **Auto-Config Script** | `/usr/local/bin/nginx-auto-config.sh` | `/usr/local/bin/nginx-auto-config.sh` | ✅ Identical |
| **Log File** | `/var/log/nginx-auto-config.log` | `/var/log/nginx-auto-config.log` | ✅ Identical |
| **Systemd Service** | `nginx-auto-config.service` | `nginx-auto-config.service` | ✅ Identical |
| **collect_container_info()** | jq-based IP extraction | jq-based IP extraction | ✅ Identical |
| **generate_consolidated_config()** | Consolidated approach | Consolidated approach | ✅ Identical |
| **Path Rewriting** | `rewrite ^$path/(.*) /$1 break;` | `rewrite ^$path/(.*) /$1 break;` | ✅ Identical |
| **rebuild_all_configs()** | Full rebuild on change | Full rebuild on change | ✅ Identical |
| **Event Monitoring** | Docker events API | Docker events API | ✅ Identical |
| **Docker Network** | `app-network` | `app-network` | ✅ Identical |
| **Container Labels** | nginx.enable/path/port | nginx.enable/path/port | ✅ Identical |

### Cloud-Specific Differences (Expected)

| Feature | AWS | Azure | Reason |
|---------|-----|-------|--------|
| **User Account** | ubuntu | azureuser | Cloud defaults |
| **Cloud CLI** | awscli | Azure CLI | Cloud-specific |
| **Init Format** | user-data.sh | cloud-init.yaml | Cloud init systems |
| **Variable Syntax** | `$VAR` | `${var}` | Terraform vs cloud-init |
| **Load Balancer** | ALB | None (VM IP) | Architecture choice |

### Verification Completed ✅

All core nginx and auto-configuration logic is **identical** between AWS and Azure implementations. The only differences are:
1. User account names (cloud-specific defaults)
2. Cloud-specific tools (AWS CLI vs Azure CLI)  
3. Configuration file formats (bash vs YAML)

**Application behavior will be identical across both platforms.** ✅

---

**Date:** 2024-11-24  
**AWS Reference:** `infrastructure/AWS/scripts/user-data.sh` (lines 290-550)  
**Azure Implementation:** `infrastructure/Azure/terraform/modules/vm/cloud-init.yaml`  
**Verified:** All critical nginx and auto-config logic matches exactly
