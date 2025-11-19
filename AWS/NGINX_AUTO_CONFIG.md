# Nginx Automated Configuration Guide

## Overview

The EC2 instance includes an **automated Nginx configuration manager** that watches Docker containers and automatically generates Nginx configurations based on container labels. This eliminates the manual steps of creating configuration files and reloading Nginx.

## How It Works

1. **Event Monitoring**: A systemd service (`nginx-auto-config.service`) monitors Docker events
2. **Label Detection**: When a container starts on `app-network`, labels are extracted
3. **Config Generation**: Nginx upstream and server blocks are automatically created
4. **Auto-reload**: Nginx is tested and reloaded seamlessly
5. **Cleanup**: When containers stop, their configs are automatically removed

## Quick Start with Auto-Configuration

### 1. Deploy Your Service with Labels

```bash
docker run -d \
  --name payment-api \
  --network app-network \
  --label nginx.enable=true \
  --label nginx.path=/payments \
  --label nginx.port=8080 \
  payment-service:latest
```

**That's it!** The service is immediately accessible at `http://EC2_IP/payments`

No manual configuration files needed. No nginx reload required.

## Supported Labels

### `nginx.enable` (optional, default: true)
Enable or disable automatic Nginx configuration for this container.

```bash
--label nginx.enable=true   # Enable (default)
--label nginx.enable=false  # Disable auto-config
```

### `nginx.path` (optional, default: /container-name)
URL path prefix for path-based routing.

```bash
--label nginx.path=/api           # Access at /api
--label nginx.path=/payments/v1   # Access at /payments/v1
```

### `nginx.host` (optional)
Server name for host-based routing. If not specified, all hosts are accepted.

```bash
--label nginx.host=api.example.com     # Host-based routing
--label nginx.host=app.example.com     # Different subdomain
```

### `nginx.port` (optional, auto-detected)
Backend port to proxy to. Auto-detected from exposed ports if not specified.

```bash
--label nginx.port=8080  # Explicit port
--label nginx.port=3000  # Frontend port
```

## Usage Examples

### Example 1: Path-Based Routing (Simple)

Deploy multiple services accessible via different URL paths:

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
- `http://EC2_IP/payments` → payment-api
- `http://EC2_IP/users` → user-api
- `http://EC2_IP/orders` → order-api

### Example 2: Host-Based Routing

Different services on different subdomains:

```bash
# API service
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

### Example 3: Docker Compose with Auto-Config

```yaml
version: '3.8'

services:
  backend:
    image: my-backend:latest
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.path: "/api"
      nginx.port: "8080"
  
  frontend:
    image: my-frontend:latest
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.host: "app.example.com"
      nginx.port: "3000"
  
  metrics:
    image: prometheus:latest
    networks:
      - app-network
    labels:
      nginx.enable: "true"
      nginx.path: "/metrics"
      nginx.port: "9090"

networks:
  app-network:
    external: true
```

Deploy: `docker compose up -d`

All services are immediately accessible through Nginx!

### Example 4: Disable Auto-Config

If you want manual control for specific containers:

```bash
# Deploy without auto-config
docker run -d \
  --name special-service \
  --network app-network \
  --label nginx.enable=false \
  special-service:latest

# Then manually create /opt/nginx/conf.d/special-service.conf
# with your custom configuration
```

## Monitoring and Troubleshooting

### View Auto-Config Logs

```bash
# Real-time logs
tail -f /var/log/nginx-auto-config.log

# Last 50 lines
tail -50 /var/log/nginx-auto-config.log

# Search for specific container
grep "payment-api" /var/log/nginx-auto-config.log
```

### Check Service Status

```bash
# Check if auto-config service is running
systemctl status nginx-auto-config.service

# Restart the service
systemctl restart nginx-auto-config.service

# View service logs
journalctl -u nginx-auto-config.service -f
```

### View Generated Configs

```bash
# List all auto-generated configs
ls -la /opt/nginx/conf.d/auto-generated/

# View a specific config
cat /opt/nginx/conf.d/auto-generated/payment-api.conf

# Validate all configs
docker exec nginx nginx -t
```

### Troubleshooting Common Issues

#### Container not being configured

**Check 1: Is container on app-network?**
```bash
docker inspect payment-api | grep -A 10 Networks
```

**Check 2: Check labels**
```bash
docker inspect payment-api | grep -A 10 Labels
```

**Check 3: Review auto-config logs**
```bash
tail -50 /var/log/nginx-auto-config.log
```

#### Configuration not working

**Test Nginx config:**
```bash
docker exec nginx nginx -t
```

**View Nginx error logs:**
```bash
docker logs nginx
docker exec nginx tail -50 /var/log/nginx/error.log
```

**Manually reload Nginx:**
```bash
docker exec nginx nginx -s reload
```

#### Service stopped but config remains

Normally configs are auto-removed when containers stop. If not:

```bash
# Manually remove stale config
rm /opt/nginx/conf.d/auto-generated/old-service.conf

# Reload Nginx
docker exec nginx nginx -s reload
```

## Generated Configuration Format

For reference, here's what the auto-config service generates:

### Path-Based Routing Config

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

### Host-Based Routing Config

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

## Advanced: Manual Configuration Override

For complex scenarios requiring custom Nginx configurations, you can:

1. **Disable auto-config for that container**: Use `--label nginx.enable=false`
2. **Create manual config**: Add custom config to `/opt/nginx/conf.d/`
3. **Mix both approaches**: Auto-config for most services, manual for special cases

See [NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md) for manual configuration examples.

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Deploy Service with Auto-Config
  run: |
    docker run -d \
      --name ${{ github.event.repository.name }} \
      --network app-network \
      --label nginx.enable=true \
      --label nginx.path=/${{ github.event.repository.name }} \
      --label nginx.port=8080 \
      ${{ env.IMAGE_TAG }}
    
    # Service is immediately accessible - no config files needed!
    echo "Service deployed and accessible at http://$EC2_IP/${{ github.event.repository.name }}"
```

## Features

✅ **Zero Configuration**: Deploy containers with labels, everything else is automatic  
✅ **Event-Driven**: Watches Docker events in real-time  
✅ **Auto-Reload**: Nginx reloaded automatically after config changes  
✅ **Auto-Cleanup**: Removes configs when containers stop  
✅ **WebSocket Support**: Generated configs include WebSocket headers  
✅ **Logging**: All operations logged to `/var/log/nginx-auto-config.log`  
✅ **Network Isolation**: Only processes containers on `app-network`  
✅ **Resilient**: Systemd service auto-restarts on failure  

## Comparison: Manual vs Auto-Config

### Manual Configuration (Old Way)

```bash
# 1. Deploy container
docker run -d --name api --network app-network api:latest

# 2. Create config file
cat > /opt/nginx/conf.d/api.conf <<EOF
upstream api_backend { server api:8080; }
server {
    listen 80;
    location /api { proxy_pass http://api_backend; }
}
EOF

# 3. Reload Nginx
docker exec nginx nginx -s reload

# 4. When removing, cleanup config
docker stop api
docker rm api
rm /opt/nginx/conf.d/api.conf
docker exec nginx nginx -s reload
```

### Auto-Configuration (New Way)

```bash
# 1. Deploy container with labels - DONE!
docker run -d \
  --name api \
  --network app-network \
  --label nginx.path=/api \
  api:latest

# Everything else happens automatically ✨
```

## Reference

- **Service**: `nginx-auto-config.service`
- **Script**: `/opt/nginx/auto-config.sh`
- **Logs**: `/var/log/nginx-auto-config.log`
- **Generated Configs**: `/opt/nginx/conf.d/auto-generated/`
- **Network**: `app-network` (only containers on this network are configured)

## Summary

The automated Nginx configuration eliminates manual steps and makes deploying containerized services as simple as:

```bash
docker run -d \
  --name my-service \
  --network app-network \
  --label nginx.path=/my-service \
  my-service:latest
```

Your service is immediately accessible through Nginx with proper headers, timeouts, and WebSocket support!
