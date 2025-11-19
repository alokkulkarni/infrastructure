# Complete Nginx Configuration Guide for Azure

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Automated Configuration (Recommended)](#automated-configuration-recommended)
4. [Manual Configuration (Advanced)](#manual-configuration-advanced)
5. [Docker Compose Integration](#docker-compose-integration)
6. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
7. [Common Patterns](#common-patterns)
8. [Security Best Practices](#security-best-practices)

---

## Overview

The Azure VM includes an **automated Nginx configuration manager** that eliminates manual configuration steps. Simply deploy containers with Docker labels, and Nginx is automatically configured.

### What's Automated

✅ **Watches** Docker container events (start/stop)  
✅ **Detects** containers on `app-network`  
✅ **Reads** nginx.* labels from containers  
✅ **Generates** Nginx upstream and server blocks  
✅ **Tests** configuration with `nginx -t`  
✅ **Reloads** Nginx automatically  
✅ **Cleans up** configs when containers stop  

### Key Benefits

- **Zero manual configuration** - No config files to create
- **No nginx reload needed** - Automatic reload
- **No cleanup required** - Auto-removes configs
- **Instant deployment** - Containers immediately accessible

---

## Architecture

```
Internet → VM (Port 80/443) → Nginx Container → app-network → Your Services
                                    ↑
                        Auto-Config Service watches Docker events
```

### Components

| Component | Description | Location |
|-----------|-------------|----------|
| **Nginx Container** | Reverse proxy | Docker container named `nginx` |
| **Auto-Config Service** | Event monitor | `nginx-auto-config.service` (systemd) |
| **Auto-Config Script** | Config generator | `/opt/nginx/auto-config.sh` |
| **Docker Network** | Service network | `app-network` (bridge) |
| **Generated Configs** | Auto-generated files | `/opt/nginx/conf.d/auto-generated/` |
| **Manual Configs** | Custom configs | `/opt/nginx/conf.d/` |
| **Logs** | Service logs | `/var/log/nginx-auto-config.log` |

---

## Automated Configuration (Recommended)

### Quick Start

Deploy a container with labels - that's it!

```bash
docker run -d \
  --name payment-api \
  --network app-network \
  --label nginx.path=/payments \
  --label nginx.port=8080 \
  payment-service:latest
```

**Result:** Immediately accessible at `http://VM_IP/payments`

### Docker Labels Reference

| Label | Required | Default | Description | Example |
|-------|----------|---------|-------------|---------|
| `nginx.enable` | No | `true` | Enable/disable auto-config | `nginx.enable=true` |
| `nginx.path` | No | `/container-name` | URL path prefix | `nginx.path=/api` |
| `nginx.host` | No | (none) | Server name for host routing | `nginx.host=api.example.com` |
| `nginx.port` | No | auto-detect | Backend port | `nginx.port=8080` |

### Usage Examples

#### Example 1: Simple Path-Based Routing

Deploy multiple microservices with different URL paths:

```bash
# Payment service at /payments
docker run -d \
  --name payment-api \
  --network app-network \
  --label nginx.path=/payments \
  --label nginx.port=8080 \
  payment-service:latest

# User service at /users
docker run -d \
  --name user-api \
  --network app-network \
  --label nginx.path=/users \
  --label nginx.port=8081 \
  user-service:latest

# Order service at /orders
docker run -d \
  --name order-api \
  --network app-network \
  --label nginx.path=/orders \
  --label nginx.port=8082 \
  order-service:latest
```

**Access:**
- `http://VM_IP/payments` → payment-api
- `http://VM_IP/users` → user-api
- `http://VM_IP/orders` → order-api

#### Example 2: Host-Based Routing

Different services on different subdomains:

```bash
# API backend
docker run -d \
  --name api-backend \
  --network app-network \
  --label nginx.host=api.example.com \
  --label nginx.port=8080 \
  api-service:latest

# Web frontend
docker run -d \
  --name web-frontend \
  --network app-network \
  --label nginx.host=app.example.com \
  --label nginx.port=3000 \
  web-app:latest

# Admin panel
docker run -d \
  --name admin-panel \
  --network app-network \
  --label nginx.host=admin.example.com \
  --label nginx.port=4000 \
  admin-app:latest
```

**Access (with DNS configured):**
- `http://api.example.com` → api-backend
- `http://app.example.com` → web-frontend
- `http://admin.example.com` → admin-panel

#### Example 3: Mixed Routing

Combine path-based and host-based routing:

```bash
# Main API (host-based)
docker run -d \
  --name main-api \
  --network app-network \
  --label nginx.host=api.example.com \
  --label nginx.port=8080 \
  api:latest

# Metrics endpoint (path-based)
docker run -d \
  --name prometheus \
  --network app-network \
  --label nginx.path=/metrics \
  --label nginx.port=9090 \
  prom/prometheus:latest

# Health checks (path-based)
docker run -d \
  --name health-checker \
  --network app-network \
  --label nginx.path=/health \
  --label nginx.port=8000 \
  health-service:latest
```

#### Example 4: Disable Auto-Config

When you need full manual control:

```bash
# Deploy without auto-config
docker run -d \
  --name special-service \
  --network app-network \
  --label nginx.enable=false \
  special-service:latest

# Then create manual config (see Manual Configuration section)
```

### What Gets Generated

For reference, here's what the auto-config service creates:

#### Path-Based Config Example

```nginx
upstream payment-api_backend {
    server payment-api:8080;
}

server {
    listen 80;
    
    location /payments {
        proxy_pass http://payment-api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

#### Host-Based Config Example

```nginx
upstream api-service_backend {
    server api-service:8080;
}

server {
    listen 80;
    server_name api.example.com;
    
    location / {
        proxy_pass http://api-service_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

---

## Manual Configuration (Advanced)

For complex scenarios requiring custom Nginx configurations.

### When to Use Manual Configuration

- Load balancing across multiple instances
- Custom caching rules
- Rate limiting
- SSL/TLS termination
- Complex routing logic
- Custom headers or authentication

### Step-by-Step Manual Configuration

#### Step 1: Disable Auto-Config

```bash
docker run -d \
  --name my-service \
  --network app-network \
  --label nginx.enable=false \
  my-service:latest
```

#### Step 2: Connect to VM

Use Azure Bastion, serial console, or if configured, SSH.

#### Step 3: Create Configuration File

```bash
sudo nano /opt/nginx/conf.d/my-service.conf
```

#### Step 4: Add Your Configuration

```nginx
upstream my_service_backend {
    server service1:8080 max_fails=3 fail_timeout=30s;
    server service2:8080 max_fails=3 fail_timeout=30s;
    server service3:8080 backup;
}

server {
    listen 80;
    server_name myservice.example.com;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    location / {
        limit_req zone=api_limit burst=20 nodelay;
        
        proxy_pass http://my_service_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # Custom caching
        proxy_cache my_cache;
        proxy_cache_valid 200 60m;
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

#### Step 5: Test and Reload

```bash
# Test configuration
docker exec nginx nginx -t

# Reload if test passes
docker exec nginx nginx -s reload
```

### Manual Configuration Examples

#### Load Balancing with Health Checks

```nginx
upstream backend_cluster {
    least_conn;  # Load balancing method
    
    server backend1:8080 max_fails=3 fail_timeout=30s weight=2;
    server backend2:8080 max_fails=3 fail_timeout=30s weight=2;
    server backend3:8080 max_fails=3 fail_timeout=30s weight=1;
    server backend4:8080 backup;
}

server {
    listen 80;
    server_name api.example.com;
    
    location / {
        proxy_pass http://backend_cluster;
        proxy_next_upstream error timeout http_502 http_503;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

#### WebSocket with Custom Timeouts

```nginx
upstream websocket_backend {
    server ws-service:8080;
}

server {
    listen 80;
    server_name ws.example.com;
    
    location /ws {
        proxy_pass http://websocket_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        
        # WebSocket-specific timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
    }
}
```

#### Static Files with Caching

```nginx
server {
    listen 80;
    server_name cdn.example.com;
    
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    
    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2)$ {
        root /usr/share/nginx/html;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

#### Rate Limiting and Security

```nginx
# Define rate limit zones
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;

server {
    listen 80;
    server_name api.example.com;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Public endpoints (higher rate limit)
    location /public/ {
        limit_req zone=general burst=20 nodelay;
        proxy_pass http://backend:8080/public/;
    }
    
    # API endpoints (stricter rate limit)
    location /api/ {
        limit_req zone=api burst=10 nodelay;
        proxy_pass http://backend:8080/api/;
    }
}
```

---

## Docker Compose Integration

### With Auto-Configuration

```yaml
version: '3.8'

services:
  backend:
    image: my-backend:latest
    container_name: backend-api
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.path: "/api"
      nginx.port: "8080"
    environment:
      - DB_HOST=postgres
      - REDIS_HOST=redis
  
  frontend:
    image: my-frontend:latest
    container_name: web-frontend
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.host: "app.example.com"
      nginx.port: "3000"
  
  metrics:
    image: prom/prometheus:latest
    container_name: prometheus
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.path: "/metrics"
      nginx.port: "9090"
  
  postgres:
    image: postgres:15
    container_name: postgres-db
    networks:
      - app-network
    labels:
      nginx.enable: "false"  # Database not exposed via Nginx
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=secret
  
  redis:
    image: redis:7
    container_name: redis-cache
    networks:
      - app-network
    labels:
      nginx.enable: "false"  # Cache not exposed via Nginx

networks:
  app-network:
    external: true

volumes:
  postgres-data:
```

**Deploy:**
```bash
docker-compose up -d
```

**Access:**
- `http://VM_IP/api` → backend
- `http://app.example.com` → frontend
- `http://VM_IP/metrics` → prometheus

### With Manual Configuration

If using manual configs, set `nginx.enable: "false"` for all services and create config files in `/opt/nginx/conf.d/`.

---

## Monitoring & Troubleshooting

### Check Auto-Config Service

```bash
# Check service status
systemctl status nginx-auto-config.service

# Restart service
systemctl restart nginx-auto-config.service

# Enable/disable service
systemctl enable nginx-auto-config.service
systemctl disable nginx-auto-config.service
```

### View Logs

```bash
# Auto-config service logs (real-time)
tail -f /var/log/nginx-auto-config.log

# Last 50 lines
tail -50 /var/log/nginx-auto-config.log

# Search for specific container
grep "payment-api" /var/log/nginx-auto-config.log

# Nginx container logs
docker logs nginx
docker logs -f nginx  # Follow mode

# Service logs via systemd
journalctl -u nginx-auto-config.service -f
journalctl -u nginx-auto-config.service --since "1 hour ago"
```

### Check Generated Configurations

```bash
# List all auto-generated configs
ls -la /opt/nginx/conf.d/auto-generated/

# View specific config
cat /opt/nginx/conf.d/auto-generated/payment-api.conf

# View all configs (manual + auto)
ls -la /opt/nginx/conf.d/

# Test Nginx configuration
docker exec nginx nginx -t

# View loaded configuration
docker exec nginx nginx -T
```

### Troubleshooting Guide

#### Problem: Container not being auto-configured

**Step 1: Verify container is on app-network**
```bash
docker inspect payment-api | grep -A 10 Networks
```
Look for: `"app-network": {`

**Step 2: Check labels**
```bash
docker inspect payment-api | grep -A 10 Labels
```
Look for: `"nginx.*": "..."`

**Step 3: Verify nginx.enable is not false**
```bash
docker inspect payment-api --format='{{index .Config.Labels "nginx.enable"}}'
```
Should be: empty or "true"

**Step 4: Check auto-config logs**
```bash
tail -50 /var/log/nginx-auto-config.log
```
Look for: Container start events and config generation

**Step 5: Check if service is running**
```bash
systemctl status nginx-auto-config.service
```

#### Problem: Nginx configuration error

**Step 1: Test configuration**
```bash
docker exec nginx nginx -t
```

**Step 2: View error details**
```bash
docker exec nginx cat /var/log/nginx/error.log
```

**Step 3: Check generated config**
```bash
cat /opt/nginx/conf.d/auto-generated/problematic-service.conf
```

**Step 4: Fix or remove bad config**
```bash
# Remove bad config
sudo rm /opt/nginx/conf.d/auto-generated/problematic-service.conf

# Reload Nginx
docker exec nginx nginx -s reload
```

#### Problem: Service not accessible

**Step 1: Check if container is running**
```bash
docker ps | grep my-service
```

**Step 2: Test internal connectivity**
```bash
# From Nginx container
docker exec nginx curl http://my-service:8080/health
```

**Step 3: Check port is correct**
```bash
docker inspect my-service --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{end}}'
```

**Step 4: Test from VM directly**
```bash
curl http://localhost/my-service
```

**Step 5: Check NSG allows traffic**
- Port 80 (HTTP) should be open
- Port 443 (HTTPS) should be open

#### Problem: Config not removed when container stops

**Step 1: Check auto-config logs**
```bash
grep "die\|stop" /var/log/nginx-auto-config.log | tail -20
```

**Step 2: Manually remove stale config**
```bash
sudo rm /opt/nginx/conf.d/auto-generated/old-service.conf
docker exec nginx nginx -s reload
```

**Step 3: Restart auto-config service**
```bash
systemctl restart nginx-auto-config.service
```

#### Problem: Auto-config service crashed

**Step 1: Check service status**
```bash
systemctl status nginx-auto-config.service
```

**Step 2: View service logs**
```bash
journalctl -u nginx-auto-config.service --no-pager | tail -50
```

**Step 3: Restart service**
```bash
systemctl restart nginx-auto-config.service
```

**Step 4: Check for errors in script**
```bash
bash -n /opt/nginx/auto-config.sh  # Syntax check
```

### Health Checks

#### Nginx Health

```bash
# Built-in health endpoint
curl http://VM_IP/health
# Response: healthy

# Check if Nginx is running
docker ps | grep nginx

# Check Nginx processes
docker exec nginx ps aux | grep nginx
```

#### Service Health

```bash
# Check specific service (from VM)
curl http://localhost/payments/health

# Check from outside
curl http://VM_IP/payments/health
```

---

## Common Patterns

### Pattern 1: Microservices Architecture

```bash
# API Gateway (path-based routing to multiple services)
docker run -d --name auth-service --network app-network \
  --label nginx.path=/auth --label nginx.port=8001 auth:latest

docker run -d --name user-service --network app-network \
  --label nginx.path=/users --label nginx.port=8002 users:latest

docker run -d --name payment-service --network app-network \
  --label nginx.path=/payments --label nginx.port=8003 payments:latest

docker run -d --name order-service --network app-network \
  --label nginx.path=/orders --label nginx.port=8004 orders:latest

docker run -d --name notification-service --network app-network \
  --label nginx.path=/notifications --label nginx.port=8005 notifications:latest
```

**Result:** All services accessible under one domain:
- `http://VM_IP/auth/*`
- `http://VM_IP/users/*`
- `http://VM_IP/payments/*`
- `http://VM_IP/orders/*`
- `http://VM_IP/notifications/*`

### Pattern 2: Multi-Tenant SaaS

```bash
# Tenant-specific subdomains
docker run -d --name tenant-a-app --network app-network \
  --label nginx.host=tenant-a.example.com app:latest

docker run -d --name tenant-b-app --network app-network \
  --label nginx.host=tenant-b.example.com app:latest

docker run -d --name tenant-c-app --network app-network \
  --label nginx.host=tenant-c.example.com app:latest

# Shared API
docker run -d --name shared-api --network app-network \
  --label nginx.host=api.example.com api:latest
```

### Pattern 3: Blue-Green Deployment

```bash
# Blue (current production)
docker run -d --name app-blue --network app-network \
  --label nginx.host=app.example.com --label nginx.port=8080 app:v1.0

# Green (new version - different host for testing)
docker run -d --name app-green --network app-network \
  --label nginx.host=staging.example.com --label nginx.port=8080 app:v2.0

# Test green deployment: http://staging.example.com
# When ready, stop blue and update green's host label:

docker stop app-blue
docker rm app-blue
docker stop app-green
docker rm app-green

docker run -d --name app-green --network app-network \
  --label nginx.host=app.example.com --label nginx.port=8080 app:v2.0
```

### Pattern 4: API Versioning

```bash
# API v1
docker run -d --name api-v1 --network app-network \
  --label nginx.path=/api/v1 --label nginx.port=8001 api:v1

# API v2
docker run -d --name api-v2 --network app-network \
  --label nginx.path=/api/v2 --label nginx.port=8002 api:v2

# API v3 (latest)
docker run -d --name api-v3 --network app-network \
  --label nginx.path=/api/v3 --label nginx.port=8003 api:v3
```

### Pattern 5: Development Environment

```bash
# Developer 1's environment
docker run -d --name dev1-frontend --network app-network \
  --label nginx.host=dev1.example.com frontend:dev

docker run -d --name dev1-backend --network app-network \
  --label nginx.host=api-dev1.example.com backend:dev

# Developer 2's environment
docker run -d --name dev2-frontend --network app-network \
  --label nginx.host=dev2.example.com frontend:dev

docker run -d --name dev2-backend --network app-network \
  --label nginx.host=api-dev2.example.com backend:dev
```

---

## Security Best Practices

### 1. Use HTTPS in Production

For production environments, configure SSL/TLS certificates:

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://backend:8080;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}
```

### 2. Implement Rate Limiting

Prevent abuse with rate limiting:

```bash
# Create manual config for rate limiting
cat > /opt/nginx/conf.d/rate-limits.conf <<'EOF'
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
EOF
```

### 3. Add Security Headers

```nginx
# Add to server block
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Content-Security-Policy "default-src 'self'" always;
```

### 4. IP Whitelisting

```nginx
# Allow specific IPs only
location /admin {
    allow 203.0.113.0/24;
    allow 198.51.100.50;
    deny all;
    
    proxy_pass http://admin-service:8080;
}
```

### 5. Disable nginx.enable for Internal Services

```bash
# Database - should NOT be accessible via Nginx
docker run -d --name postgres --network app-network \
  --label nginx.enable=false postgres:15

# Redis - internal cache only
docker run -d --name redis --network app-network \
  --label nginx.enable=false redis:7

# RabbitMQ - internal message queue
docker run -d --name rabbitmq --network app-network \
  --label nginx.enable=false rabbitmq:3
```

### 6. Use Environment-Specific Labels

```bash
# Production - use domain
docker run -d --name app --network app-network \
  --label nginx.host=app.example.com \
  -e ENV=production app:latest

# Staging - use subdomain
docker run -d --name app --network app-network \
  --label nginx.host=staging.example.com \
  -e ENV=staging app:latest

# Development - use path
docker run -d --name app --network app-network \
  --label nginx.path=/dev \
  -e ENV=development app:latest
```

---

## Accessing the Azure VM

Connect via Azure Bastion, serial console, or SSH (if configured).

### Via Azure CLI

```bash
# Run command on VM
az vm run-command invoke \
  --resource-group <resource-group> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "docker ps"

# View output
az vm run-command show \
  --resource-group <resource-group> \
  --name <vm-name> \
  --run-command-name <command-name>
```

### Via Azure Portal

1. Go to **Virtual Machines** → Select your VM
2. Click **Bastion** or **Serial console**
3. Connect and authenticate

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Service

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker Image
        run: docker build -t my-service:${{ github.sha }} .
      
      - name: Push to Registry
        run: |
          docker tag my-service:${{ github.sha }} registry.example.com/my-service:latest
          docker push registry.example.com/my-service:latest
      
      - name: Deploy to Azure VM
        run: |
          az vm run-command invoke \
            --resource-group <rg> \
            --name <vm-name> \
            --command-id RunShellScript \
            --scripts "docker pull registry.example.com/my-service:latest && \
              docker stop my-service || true && \
              docker rm my-service || true && \
              docker run -d --name my-service --network app-network --label nginx.path=/my-service --label nginx.port=8080 registry.example.com/my-service:latest"
```

**Result:** Service automatically configured in Nginx upon deployment!

---

## Quick Reference

### Deployment Commands

```bash
# Simple deployment
docker run -d --name app --network app-network --label nginx.path=/app app:latest

# With specific port
docker run -d --name app --network app-network --label nginx.path=/app --label nginx.port=8080 app:latest

# With custom host
docker run -d --name app --network app-network --label nginx.host=app.example.com app:latest

# Disable auto-config
docker run -d --name app --network app-network --label nginx.enable=false app:latest
```

### Monitoring Commands

```bash
# Watch auto-config logs
tail -f /var/log/nginx-auto-config.log

# Check service
systemctl status nginx-auto-config.service

# List configs
ls -l /opt/nginx/conf.d/auto-generated/

# Test Nginx
docker exec nginx nginx -t

# Reload Nginx manually
docker exec nginx nginx -s reload
```

### Troubleshooting Commands

```bash
# Check container network
docker inspect <container> | grep -A 10 Networks

# Check labels
docker inspect <container> | grep -A 10 Labels

# Test connectivity
docker exec nginx curl http://<container>:8080

# View Nginx logs
docker logs nginx
```

---

## Summary

### Automated Configuration (Recommended)

1. Deploy container with `--network app-network`
2. Add `nginx.path` or `nginx.host` label
3. Done! Service is immediately accessible

### Manual Configuration (Advanced)

1. Deploy with `--label nginx.enable=false`
2. Create config in `/opt/nginx/conf.d/`
3. Test with `docker exec nginx nginx -t`
4. Reload with `docker exec nginx nginx -s reload`

### Key Files and Locations

- **Service:** `nginx-auto-config.service`
- **Script:** `/opt/nginx/auto-config.sh`
- **Logs:** `/var/log/nginx-auto-config.log`
- **Auto Configs:** `/opt/nginx/conf.d/auto-generated/`
- **Manual Configs:** `/opt/nginx/conf.d/`
- **Nginx Container:** `nginx` (on app-network)

### Support

For issues:
1. Check `/var/log/nginx-auto-config.log`
2. Verify `systemctl status nginx-auto-config.service`
3. Check labels: `docker inspect <container> | grep Labels`
4. Test config: `docker exec nginx nginx -t`
5. Review this guide's troubleshooting section
