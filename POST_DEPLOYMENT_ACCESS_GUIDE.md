# Post-Deployment Application Access Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Deployment Flow](#deployment-flow)
3. [After Infrastructure Deployment](#after-infrastructure-deployment)
4. [After Application Deployment](#after-application-deployment)
5. [Verifying Nginx Registration](#verifying-nginx-registration)
6. [Accessing Applications](#accessing-applications)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This guide explains how to verify and access your applications after:
1. **Infrastructure is deployed** (AWS or Azure VM with Nginx)
2. **Runner is registered** (GitHub Actions self-hosted runner configured)
3. **Applications are deployed** (via sit-environment-generic.yml workflow)

### Key Architecture Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Internet / Your Browser                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  ALB (AWS) or   │
                    │  Public IP      │
                    │  (Port 80/443)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  EC2 / Azure VM │
                    │  (Self-Hosted   │
                    │   Runner)       │
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
    ┌─────▼─────┐    ┌──────▼──────┐    ┌─────▼─────┐
    │  Native   │    │   Docker    │    │  Docker   │
    │  Nginx    │───►│   Network   │───►│Containers │
    │ (Port 80) │    │(app-network)│    │(Services) │
    └───────────┘    └─────────────┘    └───────────┘
          ▲
          │
    ┌─────┴─────┐
    │ Auto-     │
    │ Config    │
    │ Service   │
    └───────────┘
```

---

## Deployment Flow

### Phase 1: Infrastructure Deployment ✅

**What Happens:**
```bash
# You run the infrastructure deployment
gh workflow run deploy-aws-infrastructure.yml
# or
gh workflow run deploy-azure-infrastructure.yml
```

**Outputs:**
- ✅ VPC/Network created
- ✅ EC2/VM instance created
- ✅ Nginx installed (native, not Docker)
- ✅ Docker & Docker Compose installed
- ✅ `app-network` Docker network created
- ✅ Nginx auto-config service running
- ✅ **ALB URL or Public IP** provided

**Where to Find Access URLs:**

1. **GitHub Actions Summary**
   - Go to the workflow run
   - Check the **"Outputs"** section
   - Look for: `nginx_health_url`, `alb_dns_name`, or `public_ip`

2. **Terraform Outputs** (AWS)
   ```bash
   cd infrastructure/AWS/terraform
   terraform output
   ```
   
   Expected outputs:
   ```
   alb_dns_name = "testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com"
   nginx_health_url = "http://testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com/health"
   runner_instance_id = "i-0123456789abcdef0"
   ```

3. **Terraform Outputs** (Azure)
   ```bash
   cd infrastructure/Azure/terraform
   terraform output
   ```
   
   Expected outputs:
   ```
   vm_public_ip = "20.123.45.67"
   nginx_health_url = "http://20.123.45.67/health"
   vm_name = "testcontainers-vm-dev"
   ```

**Verify Infrastructure:**

```bash
# Test Nginx health endpoint
curl http://<ALB_DNS_or_PUBLIC_IP>/health

# Expected response:
# Nginx reverse proxy is running
```

### Phase 2: Runner Registration ✅

**What Happens:**
- GitHub Actions runner is installed on the VM
- Runner registers with your repository
- Runner appears in: `https://github.com/YOUR_USERNAME/YOUR_REPO/settings/actions/runners`

**Verify Runner:**

1. **GitHub UI:**
   - Go to your repository
   - Settings → Actions → Runners
   - Look for runner with label: `[self-hosted, Linux, X64, aws]` or `[self-hosted, Linux, X64, azure]`
   - Status should be: 🟢 **Idle** or 🟡 **Active**

2. **Command Line:**
   ```bash
   # List workflow runs on the runner
   gh run list --limit 5
   ```

### Phase 3: Application Deployment 🚀

**What Happens:**
```bash
# You run the sit-environment-generic workflow
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev-env \
  -f compose_file=docker-compose.yml
```

**The Workflow:**
1. ✅ Clones `sit-test-repo` to the runner
2. ✅ Calculates unique port offset for your environment
3. ✅ Exports port environment variables
4. ✅ Runs `docker-compose up -d` on the runner
5. ✅ Containers start on `app-network`
6. ✅ **Nginx auto-config service detects containers** (if labels present)
7. ✅ **Nginx configs automatically generated** (if labels present)
8. ✅ Health checks performed

---

## After Infrastructure Deployment

### Step 1: Verify Nginx is Running

```bash
# Test health endpoint
curl -i http://<ALB_DNS_or_PUBLIC_IP>/health

# Expected response:
HTTP/1.1 200 OK
Content-Type: text/plain

Nginx reverse proxy is running
```

### Step 2: Verify Auto-Config Service (SSH/SSM Required)

**AWS (via Systems Manager):**
```bash
# Get instance ID from terraform outputs
INSTANCE_ID=$(cd infrastructure/AWS/terraform && terraform output -raw runner_instance_id)

# Connect to instance
aws ssm start-session --target $INSTANCE_ID

# Once connected, check auto-config service
systemctl status nginx-auto-config.service
```

**Azure (via Bastion or Serial Console):**
```bash
# After connecting to VM
systemctl status nginx-auto-config.service
```

**Expected Output:**
```
● nginx-auto-config.service - Nginx Auto Configuration for Docker Containers
   Loaded: loaded (/etc/systemd/system/nginx-auto-config.service; enabled)
   Active: active (running) since ...
```

### Step 3: Verify Docker Network

```bash
# On the VM (via SSH/SSM)
docker network ls | grep app-network

# Expected output:
# abc123def456   app-network   bridge   local
```

---

## After Application Deployment

### Step 1: Check GitHub Actions Workflow Summary

After running the `sit-environment-generic.yml` workflow, check the **Actions** tab:

1. Go to: `https://github.com/YOUR_USERNAME/sit-test-repo/actions`
2. Click on the latest workflow run
3. Scroll to **"Summary"** section

**You should see:**

```markdown
## Generic SIT Environment Management Summary

**Action:** deploy
**Environment Name:** dev-env
**Compose Project:** sit-dev-env
**Status:** success

---

### 🌐 Service Endpoints (Port Offset: 247)

| Variable | Port |
|----------|------|
| BENEFICIARIES_PORT | 8327 |
| PAYMENTPROCESSOR_PORT | 8328 |
| PAYMENTCONSUMER_PORT | 8329 |
| BENEFICIARIES_DB_PORT | 5679 |
| PAYMENTPROCESSOR_DB_PORT | 5680 |
| REDIS_PORT | 6626 |

💡 **Tip:** Save these port numbers! They're unique to your environment name (dev-env)
```

### Step 2: Understanding Port Access

⚠️ **IMPORTANT:** The ports shown (8327, 8328, etc.) are **INTERNAL to the VM/EC2 instance**.

**Two Ways to Access:**

#### Option A: Via Nginx Reverse Proxy (External Access) 🌐

**This requires Nginx labels to be configured in docker-compose.yml**

Currently, your `sit-test-repo/docker-compose.yml` **DOES NOT** have Nginx labels.

To enable external access, you need to add labels:

```yaml
services:
  beneficiaries:
    image: ghcr.io/alokkulkarni/beneficiaries:latest
    # ... existing config ...
    labels:
      nginx.enable: "true"
      nginx.path: "/dev/beneficiaries"  # Access at /dev/beneficiaries
      nginx.port: "8080"  # Container internal port
    # ... rest of config ...
```

#### Option B: Direct Port Access (Internal/Testing Only) 🔒

**Only accessible if you SSH/SSM into the VM:**

```bash
# On the VM
curl http://localhost:8327/actuator/health  # Beneficiaries
curl http://localhost:8328/actuator/health  # Payment Processor
curl http://localhost:8329/actuator/health  # Payment Consumer
```

---

## Verifying Nginx Registration

### Understanding Nginx Auto-Config

The **nginx-auto-config service** watches Docker events and automatically configures Nginx when containers with proper labels start.

### Check if Containers Have Nginx Labels

**On the VM (via SSH/SSM):**

```bash
# Check beneficiaries container labels
docker inspect sit-dev-env-beneficiaries-1 | grep -A 10 "Labels"

# Check if nginx.enable label exists
docker inspect sit-dev-env-beneficiaries-1 \
  --format='{{index .Config.Labels "nginx.enable"}}'
```

**Current Status:** Your docker-compose.yml **does not have nginx labels**, so:
- ❌ Containers will NOT be auto-registered with Nginx
- ❌ Services will NOT be accessible via ALB/Public IP
- ✅ Services ARE accessible internally on the VM

### Verify Auto-Config Generated Configs

**If labels were present**, you would check:

```bash
# On the VM
ls -la /etc/nginx/conf.d/auto-generated/

# Expected files (if labels present):
# sit-dev-env-beneficiaries-1.conf
# sit-dev-env-paymentprocessor-1.conf
# sit-dev-env-paymentconsumer-1.conf
```

### View Auto-Config Logs

```bash
# On the VM
tail -f /var/log/nginx-auto-config.log

# Or with systemd
journalctl -u nginx-auto-config.service -f
```

**What to look for:**
- `Container started: sit-dev-env-beneficiaries-1` - Container detected
- `Container has nginx.enable label: true` - Label found
- `Generated nginx config for: sit-dev-env-beneficiaries-1` - Config created
- `Nginx configuration test passed` - nginx -t successful
- `Nginx reloaded successfully` - Service accessible

**If labels are missing:**
- `Container has nginx.enable label: false` - Not registered
- OR no mention of the container at all

---

## Accessing Applications

### Scenario 1: With Nginx Labels Configured ✅

**Update docker-compose.yml** to add labels:

```yaml
services:
  beneficiaries:
    image: ghcr.io/alokkulkarni/beneficiaries:latest
    # ... existing config ...
    labels:
      nginx.enable: "true"
      nginx.path: "/dev/beneficiaries"
      nginx.port: "8080"
    networks:
      - payment-network  # MUST be on app-network for AWS!
    # ... rest of config ...

  paymentprocessor:
    image: ghcr.io/alokkulkarni/paymentprocessor:latest
    # ... existing config ...
    labels:
      nginx.enable: "true"
      nginx.path: "/dev/paymentprocessor"
      nginx.port: "8081"
    networks:
      - payment-network  # MUST be on app-network for AWS!
    # ... rest of config ...

  paymentconsumer:
    image: ghcr.io/alokkulkarni/paymentconsumer/paymentconsumer:latest
    # ... existing config ...
    labels:
      nginx.enable: "true"
      nginx.path: "/dev/paymentconsumer"
      nginx.port: "8082"
    networks:
      - payment-network  # MUST be on app-network for AWS!
    # ... rest of config ...
```

⚠️ **IMPORTANT for AWS:** Your docker-compose.yml uses network name `payment-network`, but AWS expects `app-network`. You have two options:

**Option 1: Change your network to app-network (Recommended for AWS)**
```yaml
networks:
  payment-network:
    external: true
    name: app-network  # Use the existing app-network from infrastructure
```

**Option 2: Create app-network in sit-test-repo**
```bash
# In sit-environment-generic.yml workflow, add before deploy:
docker network create app-network || true
```

**After adding labels, redeploy:**

```bash
# Teardown old environment
gh workflow run sit-environment-generic.yml \
  -f action=teardown \
  -f environment_name=dev-env

# Deploy new environment with labels
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev-env
```

**Then access via ALB/Public IP:**

```bash
# AWS
curl http://<ALB_DNS>/dev/beneficiaries/actuator/health
curl http://<ALB_DNS>/dev/paymentprocessor/actuator/health
curl http://<ALB_DNS>/dev/paymentconsumer/actuator/health

# Azure
curl http://<PUBLIC_IP>/dev/beneficiaries/actuator/health
curl http://<PUBLIC_IP>/dev/paymentprocessor/actuator/health
curl http://<PUBLIC_IP>/dev/paymentconsumer/actuator/health
```

**In your browser:**
```
http://<ALB_DNS_or_PUBLIC_IP>/dev/beneficiaries/actuator/health
http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentprocessor/actuator/health
http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentconsumer/actuator/health
```

### Scenario 2: Without Nginx Labels (Current Setup) ⚠️

**Access is ONLY possible from inside the VM:**

```bash
# SSH/SSM into the VM
aws ssm start-session --target <INSTANCE_ID>

# Then test services
curl http://localhost:8327/actuator/health  # Beneficiaries
curl http://localhost:8328/actuator/health  # Payment Processor
curl http://localhost:8329/actuator/health  # Payment Consumer
```

**External access via ALB/Public IP will NOT work** because Nginx doesn't know about your services.

---

## Troubleshooting

### Problem 1: "I deployed but can't access services via ALB/Public IP"

**Root Cause:** Nginx labels missing or auto-config not working

**Solution:**

1. **Check if labels exist:**
   ```bash
   # On VM
   docker inspect sit-dev-env-beneficiaries-1 | grep -A 5 "Labels"
   ```

2. **Check auto-config logs:**
   ```bash
   tail -50 /var/log/nginx-auto-config.log
   ```

3. **Check nginx configs:**
   ```bash
   ls -la /etc/nginx/conf.d/auto-generated/
   ```

4. **If no configs generated:**
   - Add labels to docker-compose.yml (see above)
   - Redeploy environment

### Problem 2: "Services are healthy but Nginx returns 502 Bad Gateway"

**Root Cause:** Container IP changed or not on correct network

**Solution:**

1. **Check container is on app-network:**
   ```bash
   docker inspect sit-dev-env-beneficiaries-1 | grep -A 10 "Networks"
   ```

2. **Check container IP:**
   ```bash
   docker inspect sit-dev-env-beneficiaries-1 \
     --format='{{.NetworkSettings.Networks.app-network.IPAddress}}'
   ```

3. **Verify Nginx config has correct IP:**
   ```bash
   cat /etc/nginx/conf.d/auto-generated/sit-dev-env-beneficiaries-1.conf
   ```

4. **Restart auto-config service:**
   ```bash
   systemctl restart nginx-auto-config.service
   ```

### Problem 3: "How do I know what port my environment is using?"

**Solution:**

Check the GitHub Actions workflow summary (as shown in Step 1 of "After Application Deployment")

Or SSH/SSM into VM:
```bash
# List containers with ports
docker ps --filter "name=sit-dev-env" --format "table {{.Names}}\t{{.Ports}}"
```

### Problem 4: "Nginx auto-config service not running"

**Solution:**

```bash
# Check service status
systemctl status nginx-auto-config.service

# View logs
journalctl -u nginx-auto-config.service --no-pager -n 50

# Restart service
systemctl restart nginx-auto-config.service

# Check if script has errors
bash -n /opt/nginx/auto-config.sh
```

### Problem 5: "I forgot my environment name"

**Solution:**

```bash
# List all environments
gh workflow run sit-environment-generic.yml \
  -f action=list-all \
  -f environment_name=dummy

# Or on the VM
docker ps --filter "name=sit-" --format "{{.Names}}"
```

### Problem 6: "Multiple users deployed, whose services is Nginx routing to?"

**Answer:** ALL of them! Each environment has unique container names:
- User 1: `sit-john-dev-beneficiaries-1`
- User 2: `sit-alice-test-beneficiaries-1`

Each gets unique Nginx config:
- `/etc/nginx/conf.d/auto-generated/sit-john-dev-beneficiaries-1.conf`
- `/etc/nginx/conf.d/auto-generated/sit-alice-test-beneficiaries-1.conf`

**But they need different paths or hosts:**

```yaml
# John's environment
labels:
  nginx.path: "/john/beneficiaries"  # Unique path per user

# Alice's environment  
labels:
  nginx.path: "/alice/beneficiaries"  # Different path
```

Or use host-based routing:
```yaml
# John's environment
labels:
  nginx.host: "john.example.com"

# Alice's environment
labels:
  nginx.host: "alice.example.com"
```

---

## Quick Reference Cheat Sheet

### Get Infrastructure Access URLs

**AWS:**
```bash
cd infrastructure/AWS/terraform
terraform output alb_dns_name
terraform output nginx_health_url
```

**Azure:**
```bash
cd infrastructure/Azure/terraform
terraform output vm_public_ip
terraform output nginx_health_url
```

### Verify Nginx is Running

```bash
curl http://<ALB_DNS_or_PUBLIC_IP>/health
```

### Deploy Application

```bash
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=YOUR-NAME \
  -f compose_file=docker-compose.yml
```

### Check Application Status

```bash
gh workflow run sit-environment-generic.yml \
  -f action=status \
  -f environment_name=YOUR-NAME \
  -f compose_file=docker-compose.yml
```

### Access Application (if labels configured)

```bash
# Health endpoints
curl http://<ALB_DNS_or_PUBLIC_IP>/dev/beneficiaries/actuator/health
curl http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentprocessor/actuator/health
curl http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentconsumer/actuator/health

# API endpoints
curl http://<ALB_DNS_or_PUBLIC_IP>/dev/beneficiaries/api/v1/beneficiaries
curl http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentprocessor/api/v1/payments
```

### SSH/SSM to VM for Debugging

**AWS:**
```bash
INSTANCE_ID=$(cd infrastructure/AWS/terraform && terraform output -raw runner_instance_id)
aws ssm start-session --target $INSTANCE_ID
```

**Azure:**
```bash
# Use Azure Bastion or Serial Console from Portal
```

### Check Auto-Config Logs (on VM)

```bash
tail -f /var/log/nginx-auto-config.log
systemctl status nginx-auto-config.service
ls -la /etc/nginx/conf.d/auto-generated/
```

### List All Environments

```bash
gh workflow run sit-environment-generic.yml \
  -f action=list-all \
  -f environment_name=dummy
```

---

## Summary

### Current Setup Limitation ⚠️

Your `sit-test-repo/docker-compose.yml` currently **DOES NOT** have Nginx labels, which means:

- ❌ Services are NOT auto-registered with Nginx
- ❌ Services are NOT accessible via ALB/Public IP from the internet
- ✅ Services ARE accessible internally on the VM via localhost ports

### To Enable External Access ✅

1. **Add Nginx labels** to `sit-test-repo/docker-compose.yml`
2. **Fix network name** (use `app-network` for AWS or configure external network)
3. **Redeploy** your environment
4. **Verify** Nginx auto-config detected containers
5. **Access** via ALB DNS or Public IP

### Recommended docker-compose.yml Changes

See the [docker-compose updates](#scenario-1-with-nginx-labels-configured-) section above for complete examples.

### Access Methods Summary

| Method | Requires | Access From | URL Pattern |
|--------|----------|-------------|-------------|
| **Nginx Proxy** | Labels + app-network | Internet | `http://<ALB_or_IP>/<path>` |
| **Direct Port** | None | VM only | `http://localhost:<port>` |

---

**Next Steps:**

1. ✅ Review your deployment workflow outputs for ALB/IP
2. ✅ Test Nginx health endpoint
3. ✅ Decide if you want external access (add labels) or internal only
4. ✅ Update docker-compose.yml if external access needed
5. ✅ Redeploy and verify auto-config logs
6. ✅ Access your applications!

**Need Help?**

- Check GitHub Actions workflow logs
- SSH/SSM to VM and check systemd logs
- Review `/var/log/nginx-auto-config.log`
- Verify Docker containers are on correct network
- Confirm Nginx labels are properly formatted
