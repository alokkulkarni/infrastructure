# Infrastructure Deployment Guide - docker-compose-infra.yml

## 📋 Overview

This guide covers deployment and access using `docker-compose-infra.yml` which is **infrastructure-ready** with:
- ✅ **Nginx labels pre-configured** for auto-registration
- ✅ **Uses `app-network`** (compatible with AWS/Azure infrastructure)
- ✅ **Environment-based routing** (e.g., `/production/beneficiaries`, `/dev/payments`)
- ✅ **Secure defaults** (databases not exposed via Nginx)
- ✅ **Production-ready** configuration

---

## 🎯 Key Differences from docker-compose.yml

| Feature | docker-compose.yml | docker-compose-infra.yml |
|---------|-------------------|--------------------------|
| **Network** | `payment-network` | `app-network` ✅ |
| **Nginx Labels** | ❌ Missing | ✅ Pre-configured |
| **Routing Pattern** | N/A | `/${ENVIRONMENT_NAME}/service` |
| **Database Exposure** | Enabled | Disabled via labels ✅ |
| **Environment Variables** | Hardcoded | Configurable ✅ |
| **Port Configuration** | Fixed | Dynamic with env vars ✅ |

---

## 🚀 Deployment Steps

### Step 1: Get Infrastructure Access URL

After deploying infrastructure (AWS or Azure):

**AWS:**
```bash
cd infrastructure/AWS/terraform
terraform output alb_dns_name
# Output: testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com

terraform output nginx_health_url
# Output: http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com/health
```

**Azure:**
```bash
cd infrastructure/Azure/terraform
terraform output vm_public_ip
# Output: 20.123.45.67

terraform output nginx_health_url
# Output: http://20.123.45.67/health
```

**Save this URL** - you'll use it to access all services:
```bash
# Set as environment variable for easy access
export BASE_URL="http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com"
# or
export BASE_URL="http://20.123.45.67"
```

**Verify Nginx is running:**
```bash
curl ${BASE_URL}/health
# Expected: "Nginx reverse proxy is running"
```

### Step 2: Deploy Application Using sit-environment-generic Workflow

```bash
cd sit-test-repo

gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev-env \
  -f compose_file=docker-compose-infra.yml
```

**What happens:**
1. ✅ Workflow calculates unique port offset (e.g., 247)
2. ✅ Exports environment variables:
   - `BENEFICIARIES_PORT=8327`
   - `PAYMENTPROCESSOR_PORT=8328`
   - `PAYMENTCONSUMER_PORT=8329`
   - `ENVIRONMENT_NAME=dev-env`
3. ✅ Runs `docker-compose -f docker-compose-infra.yml up -d`
4. ✅ Containers start on `app-network` with Nginx labels
5. ✅ **Nginx auto-config service detects containers**
6. ✅ **Generates Nginx configs automatically**
7. ✅ Services immediately accessible

### Step 3: Monitor Deployment

**Via GitHub Actions UI:**
1. Go to: `https://github.com/YOUR_USERNAME/sit-test-repo/actions`
2. Click on the latest workflow run
3. Monitor the "Deploy SIT Environment" step

**Expected output in workflow:**
```
🔍 Discovering services and ports from docker-compose-infra.yml...
   BENEFICIARIES_PORT: 8080 → 8327 (offset: +247)
   PAYMENTPROCESSOR_PORT: 8081 → 8328 (offset: +247)
   PAYMENTCONSUMER_PORT: 8082 → 8329 (offset: +247)
   BENEFICIARIES_DB_PORT: 5432 → 5679 (offset: +247)
   PAYMENTPROCESSOR_DB_PORT: 5433 → 5680 (offset: +247)
   REDIS_PORT: 6379 → 6626 (offset: +247)

✅ Port mappings configured and exported to environment
🔧 Starting services...
⏳ Waiting for services to be healthy...
✅ All services are healthy!
```

---

## 🌐 Access URLs and Testing

### Understanding the URL Pattern

With `docker-compose-infra.yml`, services are accessible at:

```
http://<BASE_URL>/${ENVIRONMENT_NAME}/<service-path>
```

**Example:**
- Environment name: `dev-env`
- Base URL: `http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com`
- Service: beneficiaries

**Access URL:**
```
http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com/dev-env/beneficiaries/actuator/health
```

### Complete Service URLs

Based on your `docker-compose-infra.yml` configuration:

#### Beneficiaries Service

**Nginx Label:**
```yaml
nginx.path: "/${ENVIRONMENT_NAME:-production}/beneficiaries"
```

**Access URLs:**
```bash
# Health endpoint
curl ${BASE_URL}/dev-env/beneficiaries/actuator/health

# Info endpoint
curl ${BASE_URL}/dev-env/beneficiaries/actuator/info

# API endpoints
curl ${BASE_URL}/dev-env/beneficiaries/api/v1/beneficiaries

# Swagger UI (if enabled)
open ${BASE_URL}/dev-env/beneficiaries/swagger-ui.html
```

#### Payment Processor Service

**Nginx Label:**
```yaml
nginx.path: "/${ENVIRONMENT_NAME:-production}/payments"
```

**Access URLs:**
```bash
# Health endpoint
curl ${BASE_URL}/dev-env/payments/actuator/health

# Info endpoint
curl ${BASE_URL}/dev-env/payments/actuator/info

# API endpoints
curl ${BASE_URL}/dev-env/payments/api/v1/payments

# Create payment example
curl -X POST ${BASE_URL}/dev-env/payments/api/v1/payments \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 100.00,
    "currency": "USD",
    "beneficiaryId": "123"
  }'
```

#### Payment Consumer Service

**Nginx Label:**
```yaml
nginx.path: "/${ENVIRONMENT_NAME:-production}/consumer"
```

**Access URLs:**
```bash
# Health endpoint
curl ${BASE_URL}/dev-env/consumer/actuator/health

# Info endpoint
curl ${BASE_URL}/dev-env/consumer/actuator/info

# Prometheus metrics
curl ${BASE_URL}/dev-env/consumer/actuator/prometheus
```

### Browser Access

Open these URLs in your browser:

```
http://<BASE_URL>/dev-env/beneficiaries/actuator/health
http://<BASE_URL>/dev-env/payments/actuator/health
http://<BASE_URL>/dev-env/consumer/actuator/health
```

**Example (replace with your actual URL):**
```
http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com/dev-env/beneficiaries/actuator/health
```

---

## ✅ Validation Checklist

### 1. Verify Containers Are Running

**SSH/SSM to the VM:**

**AWS:**
```bash
# Get instance ID
INSTANCE_ID=$(cd infrastructure/AWS/terraform && terraform output -raw runner_instance_id)

# Connect
aws ssm start-session --target ${INSTANCE_ID}
```

**Azure:**
```bash
# Use Azure Bastion or Serial Console from Portal
```

**Check containers:**
```bash
# List all containers with your environment name
docker ps --filter "name=sit-dev-env"

# Expected output:
# CONTAINER ID   IMAGE                                          STATUS
# abc123...      ghcr.io/alokkulkarni/beneficiaries:latest     Up 2 minutes (healthy)
# def456...      ghcr.io/alokkulkarni/paymentprocessor:latest  Up 2 minutes (healthy)
# ghi789...      ghcr.io/.../paymentconsumer:latest            Up 2 minutes (healthy)
# jkl012...      .../testcontainers/postgres:16-alpine         Up 3 minutes (healthy)
# mno345...      .../testcontainers/postgres:16-alpine         Up 3 minutes (healthy)
# pqr678...      .../testcontainers/redis:7-alpine             Up 3 minutes (healthy)
```

### 2. Verify Containers Have Nginx Labels

```bash
# Check beneficiaries container
docker inspect sit-dev-env-beneficiaries-1 | grep -A 10 "Labels"

# Expected output includes:
# "nginx.enable": "true",
# "nginx.path": "/dev-env/beneficiaries",
# "nginx.port": "8327",
```

**Detailed label check:**
```bash
# Check each label individually
echo "nginx.enable: $(docker inspect sit-dev-env-beneficiaries-1 --format='{{index .Config.Labels "nginx.enable"}}')"
echo "nginx.path: $(docker inspect sit-dev-env-beneficiaries-1 --format='{{index .Config.Labels "nginx.path"}}')"
echo "nginx.port: $(docker inspect sit-dev-env-beneficiaries-1 --format='{{index .Config.Labels "nginx.port"}}')"

# Expected output:
# nginx.enable: true
# nginx.path: /dev-env/beneficiaries
# nginx.port: 8327
```

### 3. Verify Containers Are on app-network

```bash
# Check beneficiaries network
docker inspect sit-dev-env-beneficiaries-1 | grep -A 10 "Networks"

# Should show:
# "Networks": {
#     "app-network": {
#         "IPAddress": "172.18.0.5",
#         ...
#     }
# }

# Check all containers on app-network
docker network inspect app-network --format='{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'

# Expected output:
# sit-dev-env-beneficiaries-1 172.18.0.5/16
# sit-dev-env-paymentprocessor-1 172.18.0.6/16
# sit-dev-env-paymentconsumer-1 172.18.0.7/16
# sit-dev-env-beneficiaries-db-1 172.18.0.2/16
# sit-dev-env-paymentprocessor-db-1 172.18.0.3/16
# sit-dev-env-redis-1 172.18.0.4/16
```

### 4. Verify Nginx Auto-Config Detected Containers

```bash
# Watch auto-config logs in real-time
tail -f /var/log/nginx-auto-config.log

# Or view last 50 lines
tail -50 /var/log/nginx-auto-config.log

# Look for these key messages:
```

**Expected log output:**
```
[2024-11-22 10:15:23] Container started: sit-dev-env-beneficiaries-1
[2024-11-22 10:15:23] Container has nginx.enable label: true
[2024-11-22 10:15:23] Nginx path: /dev-env/beneficiaries
[2024-11-22 10:15:23] Container port: 8327
[2024-11-22 10:15:23] Container IP: 172.18.0.5
[2024-11-22 10:15:23] Generated nginx config: /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf
[2024-11-22 10:15:23] Nginx configuration test: PASSED
[2024-11-22 10:15:23] Nginx reloaded successfully

[2024-11-22 10:15:24] Container started: sit-dev-env-paymentprocessor-1
[2024-11-22 10:15:24] Container has nginx.enable label: true
[2024-11-22 10:15:24] Nginx path: /dev-env/payments
[2024-11-22 10:15:24] Container port: 8328
[2024-11-22 10:15:24] Container IP: 172.18.0.6
[2024-11-22 10:15:24] Generated nginx config: /etc/nginx/conf.d/auto-generated/sit-dev-env-paymentprocessor-1.conf
[2024-11-22 10:15:24] Nginx configuration test: PASSED
[2024-11-22 10:15:24] Nginx reloaded successfully

[2024-11-22 10:15:25] Container started: sit-dev-env-paymentconsumer-1
[2024-11-22 10:15:25] Container has nginx.enable label: true
[2024-11-22 10:15:25] Nginx path: /dev-env/consumer
[2024-11-22 10:15:25] Container port: 8329
[2024-11-22 10:15:25] Container IP: 172.18.0.7
[2024-11-22 10:15:25] Generated nginx config: /etc/nginx/conf.d/auto-generated/sit-dev-env-paymentconsumer-1.conf
[2024-11-22 10:15:25] Nginx configuration test: PASSED
[2024-11-22 10:15:25] Nginx reloaded successfully
```

**Check via systemd:**
```bash
# Service status
systemctl status nginx-auto-config.service

# Recent logs
journalctl -u nginx-auto-config.service -n 50 --no-pager

# Follow logs
journalctl -u nginx-auto-config.service -f
```

### 5. Verify Nginx Configs Were Generated

```bash
# List generated configs
ls -la /etc/nginx/conf.d/auto-generated/

# Expected files:
# sit-dev-env-beneficiaries-1.conf
# sit-dev-env-paymentprocessor-1.conf
# sit-dev-env-paymentconsumer-1.conf
```

**View generated config for beneficiaries:**
```bash
cat /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf
```

**Expected content:**
```nginx
upstream sit-dev-env-beneficiaries-1_backend {
    server 172.18.0.5:8080;
}

server {
    listen 80;
    
    location /dev-env/beneficiaries {
        proxy_pass http://sit-dev-env-beneficiaries-1_backend;
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

**Key points to verify:**
- ✅ Upstream uses **container IP** (172.18.0.5) not DNS name
- ✅ Location path matches label: `/dev-env/beneficiaries`
- ✅ Proxy passes to container IP and **container internal port** (8080)
- ✅ All proxy headers configured correctly

### 6. Test Nginx Configuration

```bash
# Test nginx config syntax
nginx -t

# Expected output:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# View all loaded configurations
nginx -T | grep -A 20 "dev-env"
```

### 7. Test Internal Connectivity (from VM)

```bash
# Test container health directly
curl -f http://172.18.0.5:8080/actuator/health
curl -f http://172.18.0.6:8081/actuator/health
curl -f http://172.18.0.7:8082/actuator/health

# Test via localhost (host-mapped ports)
curl -f http://localhost:8327/actuator/health  # Beneficiaries
curl -f http://localhost:8328/actuator/health  # Payment Processor
curl -f http://localhost:8329/actuator/health  # Payment Consumer

# Test via Nginx (internal)
curl -f http://localhost/dev-env/beneficiaries/actuator/health
curl -f http://localhost/dev-env/payments/actuator/health
curl -f http://localhost/dev-env/consumer/actuator/health

# All should return HTTP 200 with health status JSON
```

### 8. Test External Access (from your machine)

```bash
# Use the BASE_URL from Step 1
export BASE_URL="http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com"

# Test each service
curl -i ${BASE_URL}/dev-env/beneficiaries/actuator/health
curl -i ${BASE_URL}/dev-env/payments/actuator/health
curl -i ${BASE_URL}/dev-env/consumer/actuator/health
```

**Expected output for each:**
```http
HTTP/1.1 200 OK
Server: nginx/1.18.0
Date: Fri, 22 Nov 2024 10:20:00 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
  "status": "UP",
  "components": {
    "diskSpace": {
      "status": "UP",
      "details": { ... }
    },
    "ping": {
      "status": "UP"
    }
  }
}
```

**If you get 502 Bad Gateway:**
- Check container is running: `docker ps`
- Check nginx config has correct IP: `cat /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf`
- Check auto-config logs: `tail -50 /var/log/nginx-auto-config.log`
- Restart auto-config: `systemctl restart nginx-auto-config.service`

**If you get 404 Not Found:**
- Path might be wrong - verify nginx.path label matches URL
- Check nginx config exists: `ls /etc/nginx/conf.d/auto-generated/`
- Verify nginx reloaded: `systemctl status nginx`

---

## 🧪 Complete Testing Script

Save this as `test-deployment.sh` on your local machine:

```bash
#!/bin/bash

# Set your BASE_URL (from terraform output)
BASE_URL="http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com"
ENVIRONMENT_NAME="dev-env"

echo "============================================"
echo "Testing Deployment: ${ENVIRONMENT_NAME}"
echo "Base URL: ${BASE_URL}"
echo "============================================"
echo ""

# Test Nginx health
echo "1. Testing Nginx health endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/health)
if [ "$HTTP_CODE" == "200" ]; then
  echo "   ✅ Nginx is running (HTTP ${HTTP_CODE})"
else
  echo "   ❌ Nginx health check failed (HTTP ${HTTP_CODE})"
  exit 1
fi
echo ""

# Test Beneficiaries
echo "2. Testing Beneficiaries service..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/actuator/health)
if [ "$HTTP_CODE" == "200" ]; then
  echo "   ✅ Beneficiaries is healthy (HTTP ${HTTP_CODE})"
  echo "   URL: ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/actuator/health"
else
  echo "   ❌ Beneficiaries health check failed (HTTP ${HTTP_CODE})"
fi
echo ""

# Test Payment Processor
echo "3. Testing Payment Processor service..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/${ENVIRONMENT_NAME}/payments/actuator/health)
if [ "$HTTP_CODE" == "200" ]; then
  echo "   ✅ Payment Processor is healthy (HTTP ${HTTP_CODE})"
  echo "   URL: ${BASE_URL}/${ENVIRONMENT_NAME}/payments/actuator/health"
else
  echo "   ❌ Payment Processor health check failed (HTTP ${HTTP_CODE})"
fi
echo ""

# Test Payment Consumer
echo "4. Testing Payment Consumer service..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/${ENVIRONMENT_NAME}/consumer/actuator/health)
if [ "$HTTP_CODE" == "200" ]; then
  echo "   ✅ Payment Consumer is healthy (HTTP ${HTTP_CODE})"
  echo "   URL: ${BASE_URL}/${ENVIRONMENT_NAME}/consumer/actuator/health"
else
  echo "   ❌ Payment Consumer health check failed (HTTP ${HTTP_CODE})"
fi
echo ""

# Test API endpoints
echo "5. Testing API endpoints..."

# Beneficiaries API
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/api/v1/beneficiaries)
echo "   Beneficiaries API: HTTP ${HTTP_CODE}"
echo "   URL: ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/api/v1/beneficiaries"

# Payments API
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/${ENVIRONMENT_NAME}/payments/api/v1/payments)
echo "   Payments API: HTTP ${HTTP_CODE}"
echo "   URL: ${BASE_URL}/${ENVIRONMENT_NAME}/payments/api/v1/payments"

echo ""
echo "============================================"
echo "Testing Complete!"
echo "============================================"
echo ""
echo "📋 Summary of Access URLs:"
echo ""
echo "Health Endpoints:"
echo "  Beneficiaries: ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/actuator/health"
echo "  Payments:      ${BASE_URL}/${ENVIRONMENT_NAME}/payments/actuator/health"
echo "  Consumer:      ${BASE_URL}/${ENVIRONMENT_NAME}/consumer/actuator/health"
echo ""
echo "API Endpoints:"
echo "  Beneficiaries: ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/api/v1/beneficiaries"
echo "  Payments:      ${BASE_URL}/${ENVIRONMENT_NAME}/payments/api/v1/payments"
echo ""
echo "Info Endpoints:"
echo "  Beneficiaries: ${BASE_URL}/${ENVIRONMENT_NAME}/beneficiaries/actuator/info"
echo "  Payments:      ${BASE_URL}/${ENVIRONMENT_NAME}/payments/actuator/info"
echo "  Consumer:      ${BASE_URL}/${ENVIRONMENT_NAME}/consumer/actuator/info"
echo ""
```

**Make executable and run:**
```bash
chmod +x test-deployment.sh
./test-deployment.sh
```

---

## 📊 Port Mapping Reference

### Understanding Port Configuration

With `docker-compose-infra.yml`, each environment gets unique ports calculated from a hash:

**Example for environment name "dev-env" (offset: 247):**

| Service | Container Port | Host Port | Environment Variable | Nginx Proxies To |
|---------|---------------|-----------|---------------------|------------------|
| Beneficiaries | 8080 | 8327 | `BENEFICIARIES_PORT=8327` | 172.18.0.5:8080 |
| Payment Processor | 8081 | 8328 | `PAYMENTPROCESSOR_PORT=8328` | 172.18.0.6:8081 |
| Payment Consumer | 8082 | 8329 | `PAYMENTCONSUMER_PORT=8329` | 172.18.0.7:8082 |
| Beneficiaries DB | 5432 | 5679 | `BENEFICIARIES_DB_PORT=5679` | Not exposed |
| Payment DB | 5432 | 5680 | `PAYMENTPROCESSOR_DB_PORT=5680` | Not exposed |
| Redis | 6379 | 6626 | `REDIS_PORT=6626` | Not exposed |

**Key Point:** Nginx proxies to **container IP + container internal port**, NOT host port.

### Nginx Configuration Logic

The `docker-compose-infra.yml` uses a clever nginx label:

```yaml
nginx.port: "${BENEFICIARIES_PORT:-8080}"
```

However, the **auto-config script** actually inspects the container and uses:
- Container IP from Docker network (e.g., 172.18.0.5)
- Container internal port (e.g., 8080)

So even though the label says `8327`, Nginx proxies to `172.18.0.5:8080` internally.

---

## 🔄 Multiple Environments

You can run multiple environments simultaneously with different environment names:

### Development Environment
```bash
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev \
  -f compose_file=docker-compose-infra.yml
```

**Access URLs:**
```
http://<BASE_URL>/dev/beneficiaries/actuator/health
http://<BASE_URL>/dev/payments/actuator/health
http://<BASE_URL>/dev/consumer/actuator/health
```

### Staging Environment
```bash
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=staging \
  -f compose_file=docker-compose-infra.yml
```

**Access URLs:**
```
http://<BASE_URL>/staging/beneficiaries/actuator/health
http://<BASE_URL>/staging/payments/actuator/health
http://<BASE_URL>/staging/consumer/actuator/health
```

### Per-User Environments
```bash
# John's environment
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=john \
  -f compose_file=docker-compose-infra.yml

# Alice's environment
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=alice \
  -f compose_file=docker-compose-infra.yml
```

**Access URLs:**
```
http://<BASE_URL>/john/beneficiaries/actuator/health
http://<BASE_URL>/alice/beneficiaries/actuator/health
```

**Each environment gets:**
- ✅ Unique container names
- ✅ Unique port mappings
- ✅ Unique URL paths
- ✅ Isolated data (separate volumes)
- ✅ Independent lifecycle

---

## 🐛 Troubleshooting

### Issue 1: Services Not Accessible Externally

**Symptom:** Can't access `http://<BASE_URL>/dev-env/beneficiaries/actuator/health`

**Debug Steps:**

1. **Verify Nginx is running:**
   ```bash
   curl ${BASE_URL}/health
   # Should return: "Nginx reverse proxy is running"
   ```

2. **SSH to VM and check auto-config logs:**
   ```bash
   tail -50 /var/log/nginx-auto-config.log | grep "dev-env-beneficiaries"
   ```

3. **Verify nginx config exists:**
   ```bash
   ls -la /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf
   cat /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf
   ```

4. **Test nginx config:**
   ```bash
   nginx -t
   ```

5. **Check container is on app-network:**
   ```bash
   docker inspect sit-dev-env-beneficiaries-1 | grep -A 10 "Networks"
   ```

6. **Test internal connectivity:**
   ```bash
   curl http://localhost/dev-env/beneficiaries/actuator/health
   ```

### Issue 2: 502 Bad Gateway

**Symptom:** Nginx returns 502 error

**Cause:** Container not reachable or wrong IP/port

**Fix:**

1. **Check container IP:**
   ```bash
   docker inspect sit-dev-env-beneficiaries-1 \
     --format='{{.NetworkSettings.Networks.app-network.IPAddress}}'
   ```

2. **Verify nginx config has correct IP:**
   ```bash
   cat /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf | grep server
   ```

3. **Test container directly:**
   ```bash
   docker exec nginx curl -f http://sit-dev-env-beneficiaries-1:8080/actuator/health
   ```

4. **Restart auto-config service:**
   ```bash
   systemctl restart nginx-auto-config.service
   sleep 10
   curl http://localhost/dev-env/beneficiaries/actuator/health
   ```

### Issue 3: Environment Name Not Working

**Symptom:** URL with environment name returns 404

**Debug:**

1. **Check what was deployed:**
   ```bash
   docker ps --filter "name=sit-" --format "{{.Names}}"
   ```

2. **Check nginx labels:**
   ```bash
   docker inspect sit-dev-env-beneficiaries-1 \
     --format='{{index .Config.Labels "nginx.path"}}'
   ```

3. **List all nginx configs:**
   ```bash
   ls -la /etc/nginx/conf.d/auto-generated/
   cat /etc/nginx/conf.d/auto-generated/*.conf | grep location
   ```

---

## 📚 Summary

### What docker-compose-infra.yml Provides

✅ **Pre-configured Nginx labels** - No manual setup needed  
✅ **Environment-based routing** - Clean URL separation  
✅ **Secure defaults** - Databases not exposed  
✅ **Uses app-network** - Compatible with infrastructure  
✅ **Dynamic port allocation** - Multi-user support  
✅ **Production-ready** - Security and configurability built-in  

### Access Pattern

```
http://<BASE_URL>/<ENVIRONMENT_NAME>/<SERVICE_PATH>/<ENDPOINT>
```

**Examples:**
```
http://alb.example.com/dev/beneficiaries/actuator/health
http://alb.example.com/staging/payments/api/v1/payments
http://20.123.45.67/john/consumer/actuator/info
```

### Quick Commands Reference

```bash
# Get infrastructure URL
cd infrastructure/AWS/terraform && terraform output alb_dns_name

# Deploy application
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev \
  -f compose_file=docker-compose-infra.yml

# Test access
export BASE_URL="http://your-alb-or-ip"
curl ${BASE_URL}/dev/beneficiaries/actuator/health

# Debug on VM
aws ssm start-session --target <instance-id>
tail -f /var/log/nginx-auto-config.log
ls /etc/nginx/conf.d/auto-generated/
docker ps --filter "name=sit-dev"
```

---

**You're all set! 🚀** Your applications are accessible via the ALB/Public IP with clean, environment-based URLs.
