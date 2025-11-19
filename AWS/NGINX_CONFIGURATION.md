# Nginx Reverse Proxy Configuration Guide

## Overview

The EC2 instance runs Nginx as a Docker container that acts as a reverse proxy for all your Docker services. This setup allows external users to access your containerized applications through Nginx on port 80/443, while your services run on internal Docker networks.

## Architecture

```
Internet → EC2 (Port 80/443) → Nginx Container → app-network → Your Services
```

- **Nginx**: Runs as a Docker container named `nginx`
- **Network**: Uses Docker bridge network `app-network` for service discovery
- **Config Location**: `/opt/nginx/` on the EC2 instance
- **Service Discovery**: Uses Docker's internal DNS (127.0.0.11)

## How It Works

1. **Docker Network**: All services must be on the `app-network` Docker network
2. **Service Discovery**: Nginx uses Docker container names to route traffic
3. **Dynamic Routing**: Add configuration files to `/opt/nginx/conf.d/` to route traffic
4. **Hot Reload**: Changes take effect after reloading Nginx (no container restart needed)

## Quick Start

### 1. Deploy Your Service

```bash
# Run your service on the app-network
docker run -d \
  --name my-api \
  --network app-network \
  -p 8080:8080 \
  your-api-image:latest
```

### 2. Create Nginx Configuration

SSH alternative: Use AWS Systems Manager Session Manager to access the instance without SSH, or deploy config via your CI/CD pipeline.

Create a file at `/opt/nginx/conf.d/my-api.conf`:

```nginx
upstream api_backend {
    server my-api:8080;
}

server {
    listen 80;
    server_name api.yourdomain.com;  # or remove this for path-based routing

    location /api/ {
        proxy_pass http://api_backend/;
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
```

### 3. Reload Nginx

```bash
docker exec nginx nginx -s reload
```

### 4. Test

```bash
curl http://your-ec2-public-ip/api/health
```

## Common Patterns

### Path-Based Routing

Route different URL paths to different services:

```nginx
server {
    listen 80;
    server_name _;

    # API service
    location /api/ {
        proxy_pass http://api-service:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Web frontend
    location /app/ {
        proxy_pass http://web-frontend:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Metrics endpoint
    location /metrics {
        proxy_pass http://metrics-service:9090/metrics;
        proxy_set_header Host $host;
    }
}
```

### Host-Based Routing

Route based on domain name:

```nginx
# API domain
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://api-service:8080;
        proxy_set_header Host $host;
    }
}

# Admin domain
server {
    listen 80;
    server_name admin.example.com;

    location / {
        proxy_pass http://admin-service:3000;
        proxy_set_header Host $host;
    }
}
```

### WebSocket Support

For services using WebSockets:

```nginx
upstream websocket_backend {
    server websocket-service:8080;
}

server {
    listen 80;
    server_name ws.example.com;

    location / {
        proxy_pass http://websocket_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        # WebSocket timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

### Load Balancing

Distribute traffic across multiple instances:

```nginx
upstream app_cluster {
    # Load balancing method (default is round-robin)
    least_conn;  # or ip_hash;
    
    server app1:8080;
    server app2:8080;
    server app3:8080;
    
    # Health checks
    server app4:8080 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    server_name app.example.com;

    location / {
        proxy_pass http://app_cluster;
        proxy_set_header Host $host;
        proxy_next_upstream error timeout http_502 http_503;
    }
}
```

### Static File Serving

Serve static files directly:

```nginx
server {
    listen 80;
    server_name static.example.com;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        root /usr/share/nginx/html;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

## Docker Compose Integration

If using docker-compose, ensure services are on the correct network:

```yaml
version: '3.8'

services:
  api:
    image: your-api:latest
    container_name: api-service
    networks:
      - app-network
    ports:
      - "8080:8080"

  web:
    image: your-web:latest
    container_name: web-service
    networks:
      - app-network
    ports:
      - "3000:3000"

networks:
  app-network:
    external: true
```

## Configuration Management via CI/CD

### Using GitHub Actions

Add a step to your deployment workflow:

```yaml
- name: Deploy Nginx Configuration
  run: |
    # Create config file
    cat > my-service.conf <<'EOF'
    upstream my_service {
        server my-service:8080;
    }
    
    server {
        listen 80;
        server_name _;
        
        location /my-service/ {
            proxy_pass http://my_service/;
            proxy_set_header Host $host;
        }
    }
    EOF
    
    # Copy to EC2 (using AWS Systems Manager)
    aws ssm send-command \
      --document-name "AWS-RunShellScript" \
      --targets "Key=tag:Name,Values=testcontainers-dev-runner" \
      --parameters 'commands=["cp /tmp/my-service.conf /opt/nginx/conf.d/ && docker exec nginx nginx -s reload"]'
```

### Using Terraform

Add configuration files as part of infrastructure:

```hcl
resource "aws_s3_bucket_object" "nginx_config" {
  bucket = "your-config-bucket"
  key    = "nginx/my-service.conf"
  content = templatefile("${path.module}/nginx-configs/my-service.conf", {
    service_name = "my-service"
    service_port = 8080
  })
}
```

## Accessing the Instance (Without SSH)

Since SSH is disabled, use AWS Systems Manager Session Manager:

### Via AWS CLI

```bash
# Start a session
aws ssm start-session --target i-1234567890abcdef0

# Run a command
aws ssm send-command \
  --instance-ids i-1234567890abcdef0 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker ps"]'
```

### Via AWS Console

1. Go to EC2 → Instances
2. Select your instance
3. Click "Connect" → "Session Manager" → "Connect"

## Health Checks

Nginx provides a health check endpoint:

```bash
curl http://your-ec2-ip/health
# Response: healthy
```

## Monitoring

### View Nginx Logs

```bash
# Access logs
docker logs nginx

# Follow logs
docker logs -f nginx

# Error logs
docker exec nginx tail -f /var/log/nginx/error.log
```

### Check Nginx Status

```bash
# Test configuration
docker exec nginx nginx -t

# View loaded configuration
docker exec nginx nginx -T

# Check running processes
docker exec nginx ps aux | grep nginx
```

## Troubleshooting

### Service Not Reachable

1. **Check if service is running:**
   ```bash
   docker ps | grep my-service
   ```

2. **Verify service is on app-network:**
   ```bash
   docker network inspect app-network
   ```

3. **Test internal connectivity:**
   ```bash
   docker exec nginx curl http://my-service:8080/health
   ```

4. **Check Nginx logs:**
   ```bash
   docker logs nginx | grep error
   ```

### Configuration Errors

```bash
# Test configuration syntax
docker exec nginx nginx -t

# View detailed error messages
docker exec nginx cat /var/log/nginx/error.log
```

### Reload Issues

```bash
# If reload fails, restart the container
docker restart nginx

# Verify Nginx is running
docker ps | grep nginx
```

### Network Issues

```bash
# List all networks
docker network ls

# Inspect app-network
docker network inspect app-network

# Reconnect a service to the network
docker network connect app-network my-service
```

## Security Best Practices

1. **Use HTTPS**: Add SSL/TLS certificates for production
2. **Rate Limiting**: Implement rate limiting in Nginx configs
3. **IP Whitelisting**: Restrict access to sensitive endpoints
4. **Security Headers**: Add security headers to responses

Example security configuration:

```nginx
server {
    listen 80;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://api-service:8080/;
    }
}
```

## Advanced Configuration

### SSL/TLS Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://backend:8080;
    }
}
```

### Caching

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=1g inactive=60m;

server {
    location / {
        proxy_cache my_cache;
        proxy_cache_valid 200 60m;
        proxy_cache_bypass $http_cache_control;
        add_header X-Cache-Status $upstream_cache_status;
        
        proxy_pass http://backend:8080;
    }
}
```

## Reference

- Nginx Configuration: `/opt/nginx/nginx.conf`
- Service Configurations: `/opt/nginx/conf.d/*.conf`
- Container Name: `nginx`
- Docker Network: `app-network`
- Ports: 80 (HTTP), 443 (HTTPS)

## Support

For issues or questions:
1. Check Nginx error logs
2. Verify Docker network connectivity
3. Review this guide's troubleshooting section
4. Check Docker service logs
