# Quick Start: Accessing Your Applications

## 🚀 The Problem

After deploying infrastructure and applications, you're stuck wondering:
- ❓ How do I access my applications?
- ❓ Are they registered with Nginx?
- ❓ What URLs should I use?

## ✅ The Solution (3 Steps)

### Step 1: Get Your Access URL (After Infrastructure Deploy)

**AWS:**
```bash
cd infrastructure/AWS/terraform
terraform output alb_dns_name
```
Output: `testcontainers-alb-dev-1234567890.us-east-1.elb.amazonaws.com`

**Azure:**
```bash
cd infrastructure/Azure/terraform
terraform output vm_public_ip
```
Output: `20.123.45.67`

**Test Nginx:**
```bash
curl http://<YOUR_URL>/health
# Expected: "Nginx reverse proxy is running"
```

### Step 2: Update docker-compose.yml (One-Time Setup)

**Current Problem:** Your `sit-test-repo/docker-compose.yml` has NO Nginx labels.

**Solution:** Use the provided `docker-compose-with-nginx.yml`:

```bash
cd sit-test-repo

# Backup original
cp docker-compose.yml docker-compose-original.yml

# Use the nginx-enabled version
cp docker-compose-with-nginx.yml docker-compose.yml

# Commit changes
git add docker-compose.yml
git commit -m "Add Nginx labels for external access"
git push
```

**What Changed:**
```yaml
# Added to each service (beneficiaries, paymentprocessor, paymentconsumer):
labels:
  nginx.enable: "true"
  nginx.path: "/dev/beneficiaries"  # Unique path per service
  nginx.port: "8080"  # Container internal port
```

### Step 3: Deploy and Access

**Deploy Application:**
```bash
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=YOUR-NAME \
  -f compose_file=docker-compose.yml
```

**Access Your Services:**
```bash
# Using your ALB URL (AWS) or Public IP (Azure)
BASE_URL="http://<ALB_DNS_or_PUBLIC_IP>"

# Health endpoints
curl ${BASE_URL}/dev/beneficiaries/actuator/health
curl ${BASE_URL}/dev/paymentprocessor/actuator/health
curl ${BASE_URL}/dev/paymentconsumer/actuator/health

# API endpoints
curl ${BASE_URL}/dev/beneficiaries/api/v1/beneficiaries
curl ${BASE_URL}/dev/paymentprocessor/api/v1/payments
```

**In Your Browser:**
```
http://<ALB_DNS_or_PUBLIC_IP>/dev/beneficiaries/actuator/health
http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentprocessor/actuator/health
http://<ALB_DNS_or_PUBLIC_IP>/dev/paymentconsumer/actuator/health
```

---

## 🔍 Verification Checklist

After deployment, verify everything works:

### ✅ 1. Nginx Auto-Config Detected Containers

**SSH/SSM to VM:**
```bash
# AWS
aws ssm start-session --target <INSTANCE_ID>

# Then check logs
tail -50 /var/log/nginx-auto-config.log
```

**Look for:**
```
Container started: sit-YOUR-NAME-beneficiaries-1
Container has nginx.enable label: true
Generated nginx config for: sit-YOUR-NAME-beneficiaries-1
Nginx configuration test passed
Nginx reloaded successfully
```

### ✅ 2. Nginx Configs Were Generated

```bash
# On the VM
ls -la /etc/nginx/conf.d/auto-generated/

# Should see:
# sit-YOUR-NAME-beneficiaries-1.conf
# sit-YOUR-NAME-paymentprocessor-1.conf
# sit-YOUR-NAME-paymentconsumer-1.conf
```

### ✅ 3. View Generated Config

```bash
cat /etc/nginx/conf.d/auto-generated/sit-YOUR-NAME-beneficiaries-1.conf
```

**Expected content:**
```nginx
upstream sit-YOUR-NAME-beneficiaries-1_backend {
    server sit-YOUR-NAME-beneficiaries-1:8080;
}

server {
    listen 80;
    
    location /dev/beneficiaries {
        proxy_pass http://sit-YOUR-NAME-beneficiaries-1_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### ✅ 4. Test External Access

```bash
# From your local machine (not the VM)
curl -i http://<ALB_DNS_or_PUBLIC_IP>/dev/beneficiaries/actuator/health

# Expected: HTTP 200 OK with health status
```

---

## 🐛 Troubleshooting

### Problem: Can't Access Services Externally

**Check 1: Labels Present?**
```bash
# On VM
docker inspect sit-YOUR-NAME-beneficiaries-1 | grep -A 5 "Labels"
```

**Fix:** Update docker-compose.yml with labels (see Step 2 above)

---

**Check 2: Auto-Config Logs Show Errors?**
```bash
tail -50 /var/log/nginx-auto-config.log
```

**Common Issues:**
- `Container has nginx.enable label: false` → Labels missing
- `Network not found: app-network` → Network mismatch (see below)
- `nginx: configuration test failed` → Syntax error in generated config

---

**Check 3: Network Mismatch (AWS Only)**

Your docker-compose.yml uses `payment-network` but AWS infrastructure creates `app-network`.

**Fix - Option 1 (Recommended):** Update docker-compose.yml:
```yaml
networks:
  payment-network:
    external: true
    name: app-network  # Use existing app-network
```

**Fix - Option 2:** Create app-network in workflow:
```bash
# In sit-environment-generic.yml, before docker-compose up:
docker network create app-network 2>/dev/null || true
docker network connect app-network sit-YOUR-NAME-beneficiaries-1
```

---

**Check 4: Nginx Config Not Generated?**
```bash
ls -la /etc/nginx/conf.d/auto-generated/
# Empty directory?
```

**Fix:** Restart auto-config service:
```bash
systemctl restart nginx-auto-config.service
journalctl -u nginx-auto-config.service -f
```

---

**Check 5: 502 Bad Gateway?**

Container might be on wrong network or not reachable.

```bash
# Check container network
docker inspect sit-YOUR-NAME-beneficiaries-1 | grep -A 10 "Networks"

# Check if Nginx can reach container
docker exec nginx curl -f http://sit-YOUR-NAME-beneficiaries-1:8080/actuator/health
```

---

### Problem: Multiple Users - Whose Service Am I Accessing?

Each user gets **unique paths** based on their environment name:

**John's deployment:**
```yaml
labels:
  nginx.path: "/john/beneficiaries"
```
Access: `http://<URL>/john/beneficiaries/actuator/health`

**Alice's deployment:**
```yaml
labels:
  nginx.path: "/alice/beneficiaries"
```
Access: `http://<URL>/alice/beneficiaries/actuator/health`

**OR** use the default `/dev/<service>` and let sit-environment workflow modify paths per user automatically.

---

## 📊 Architecture Flow

```
┌─────────────────┐
│   Your Browser  │
│   curl command  │
└────────┬────────┘
         │
         │ http://<ALB_or_IP>/dev/beneficiaries/api/v1/health
         │
         ▼
┌────────────────────────────────┐
│  ALB (AWS) or Public IP (Azure)│
│        Port 80/443             │
└────────┬───────────────────────┘
         │
         │ Forwards to EC2/VM
         │
         ▼
┌────────────────────────────────┐
│      EC2 / Azure VM            │
│  ┌──────────────────────────┐  │
│  │   Native Nginx (Port 80) │  │
│  │                          │  │
│  │  Auto-Config Service     │  │
│  │  watches Docker events   │  │
│  │  generates configs       │  │
│  └────┬─────────────────────┘  │
│       │                        │
│       │ proxy_pass to container│
│       │                        │
│  ┌────▼─────────────────────┐  │
│  │  Docker app-network      │  │
│  │                          │  │
│  │  ┌────────────────────┐  │  │
│  │  │  beneficiaries     │  │  │
│  │  │  container:8080    │  │  │
│  │  └────────────────────┘  │  │
│  │                          │  │
│  │  ┌────────────────────┐  │  │
│  │  │  paymentprocessor  │  │  │
│  │  │  container:8081    │  │  │
│  │  └────────────────────┘  │  │
│  │                          │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

---

## 📝 Complete Example

### 1. Deploy Infrastructure

```bash
# AWS
cd infrastructure/AWS
gh workflow run deploy-aws-infrastructure.yml

# Get ALB URL
cd terraform
terraform output alb_dns_name
# Output: testcontainers-alb-dev-123.us-east-1.elb.amazonaws.com
```

### 2. Update sit-test-repo

```bash
cd ../../sit-test-repo

# Use nginx-enabled compose file
cp docker-compose-with-nginx.yml docker-compose.yml

git add docker-compose.yml
git commit -m "Add Nginx labels for external access"
git push
```

### 3. Deploy Application

```bash
gh workflow run sit-environment-generic.yml \
  -f action=deploy \
  -f environment_name=dev-env \
  -f compose_file=docker-compose.yml
```

### 4. Wait for Deployment

Check GitHub Actions workflow progress. Wait for ✅ success.

### 5. Verify Auto-Config (Optional)

```bash
# SSH to VM
aws ssm start-session --target i-xxxxx

# Check logs
tail -50 /var/log/nginx-auto-config.log

# List generated configs
ls -la /etc/nginx/conf.d/auto-generated/
```

### 6. Access Your Services

```bash
BASE_URL="http://testcontainers-alb-dev-123.us-east-1.elb.amazonaws.com"

# Test health
curl ${BASE_URL}/dev/beneficiaries/actuator/health
curl ${BASE_URL}/dev/paymentprocessor/actuator/health
curl ${BASE_URL}/dev/paymentconsumer/actuator/health

# Test API
curl ${BASE_URL}/dev/beneficiaries/api/v1/beneficiaries
```

**Success! 🎉**

---

## 🎯 Key Takeaways

1. **Infrastructure provides:** ALB/Public IP + Nginx + Auto-Config Service
2. **You provide:** Docker labels in docker-compose.yml
3. **Auto-Config does:** Watches containers → Generates Nginx config → Reloads Nginx
4. **Result:** Services accessible at `http://<ALB_or_IP>/<path>`

**Without labels:** Services only accessible internally on VM  
**With labels:** Services accessible externally via internet 🌐

---

## 📚 Related Documentation

- **[POST_DEPLOYMENT_ACCESS_GUIDE.md](./POST_DEPLOYMENT_ACCESS_GUIDE.md)** - Detailed troubleshooting guide
- **[AWS/NGINX_ARCHITECTURE_DECISION.md](./AWS/NGINX_ARCHITECTURE_DECISION.md)** - Why native Nginx
- **[Azure/NGINX_GUIDE.md](./Azure/NGINX_GUIDE.md)** - Complete Nginx configuration guide
- **[sit-test-repo/.github/workflows/README.md](../sit-test-repo/.github/workflows/README.md)** - Workflow documentation

---

**Still Stuck?**

1. Check GitHub Actions workflow logs
2. SSH/SSM to VM and check `/var/log/nginx-auto-config.log`
3. Verify Docker containers are running: `docker ps`
4. Verify labels exist: `docker inspect <container> | grep Labels`
5. Check auto-config service: `systemctl status nginx-auto-config.service`

**Most Common Issue:** Forgot to add Nginx labels to docker-compose.yml! ✅
