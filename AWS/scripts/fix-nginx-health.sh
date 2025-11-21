#!/bin/bash
# Quick fix script to start Nginx with health endpoint on existing EC2 instance
# This script can be run via AWS SSM or manually on the instance

set -e

echo "======================================"
echo "Nginx Health Check Fix Script"
echo "======================================"

# Check if Nginx container exists
if docker ps -a | grep -q " nginx$"; then
    echo "Nginx container exists, checking status..."
    
    if docker ps | grep -q " nginx$"; then
        echo "✅ Nginx container already running"
        echo "Checking health endpoint..."
        
        HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
        if [ "${HEALTH_CHECK}" = "200" ]; then
            echo "✅ Nginx health endpoint working correctly (200)"
            exit 0
        else
            echo "❌ Health endpoint returned: ${HEALTH_CHECK}"
            echo "Recreating Nginx container with health endpoint..."
            docker stop nginx
            docker rm nginx
        fi
    else
        echo "Nginx container stopped, removing for recreate..."
        docker rm nginx
    fi
fi

echo "Creating Nginx container with health endpoint..."

# Ensure app-network exists
if ! docker network ls | grep -q app-network; then
    echo "Creating app-network..."
    docker network create app-network
fi

# Create directories
mkdir -p /opt/nginx/conf.d/auto-generated

# Create base Nginx config with health endpoint
cat > /opt/nginx/nginx.conf <<'NGINXCONF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
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

    # Default server with health check
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        # Health check endpoint for ALB
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Default response
        location / {
            return 200 "Nginx reverse proxy is running\n";
            add_header Content-Type text/plain;
        }
    }

    # Include auto-generated and manual configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/conf.d/auto-generated/*.conf;
}
NGINXCONF

# Start Nginx container
docker run -d \
    --name nginx \
    --restart unless-stopped \
    --network app-network \
    -p 80:80 \
    -p 443:443 \
    -v /opt/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
    -v /opt/nginx/conf.d:/etc/nginx/conf.d:ro \
    nginx:alpine

# Wait for Nginx to start
echo "Waiting for Nginx to start..."
sleep 5

# Verify Nginx is running
if docker ps | grep -q " nginx$"; then
    echo "✅ Nginx container started successfully"
    
    # Test health endpoint
    sleep 2
    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
    if [ "${HEALTH_CHECK}" = "200" ]; then
        echo "✅ Nginx health endpoint responding correctly (200)"
        echo ""
        echo "Testing ALB connectivity..."
        echo "The ALB health check should now pass within 30-60 seconds"
        echo ""
        echo "You can monitor the target health with:"
        echo "  aws elbv2 describe-target-health --target-group-arn <your-target-group-arn>"
    else
        echo "⚠️  WARNING: Nginx health endpoint returned: ${HEALTH_CHECK}"
        echo "Checking Nginx logs..."
        docker logs nginx | tail -20
    fi
else
    echo "❌ Failed to start Nginx container"
    docker logs nginx 2>&1 | tail -20
    exit 1
fi

# Restart nginx-auto-config service to regenerate configs for existing containers
if systemctl is-active --quiet nginx-auto-config.service; then
    echo ""
    echo "Restarting nginx-auto-config service..."
    systemctl restart nginx-auto-config.service
    echo "✅ nginx-auto-config service restarted"
    echo ""
    echo "The service will automatically create configs for existing containers"
fi

echo ""
echo "======================================"
echo "Nginx Health Check Fix Complete"
echo "======================================"
