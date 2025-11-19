# Security Update - SSH Removed & Nginx Enhanced

## 🔒 Overview

The infrastructure has been updated with enhanced security and improved service routing capabilities:

1. **SSH Access Removed**: The EC2 instance no longer accepts SSH connections
2. **Nginx as Docker Container**: Runs in a Docker container with dynamic service discovery
3. **Transparent Access**: Services are automatically accessible through Nginx reverse proxy
4. **No Manual Configuration Required**: Everything is automated during deployment

## 🎯 Key Changes

### Security Improvements

#### ✅ SSH Access Removed
- **Before**: Security group allowed SSH (port 22) access
- **After**: No SSH ingress rules - instance is completely isolated
- **Access Method**: Use AWS Systems Manager Session Manager if needed
- **Benefit**: Eliminates SSH-based attack vectors

#### ✅ Key Management Simplified
- **Before**: Required EC2 key pair creation and management
- **After**: No SSH keys needed at all
- **Benefit**: One less credential to manage and secure

### Infrastructure Changes

#### ✅ Nginx Architecture
- **Before**: Nginx installed on EC2 instance directly
- **After**: Nginx runs as a Docker container
- **Network**: Uses Docker bridge network `app-network`
- **Benefits**:
  - Easier to update and manage
  - Consistent with containerized architecture
  - Better isolation and resource control

#### ✅ Service Discovery
- **Before**: Static proxy configuration to localhost:8080
- **After**: Dynamic routing using Docker DNS
- **How It Works**:
  ```
  Internet → EC2 → Nginx Container → Docker Network → Your Services
  ```
- **Benefits**:
  - Services referenced by container name
  - No manual IP/port configuration
  - Automatic service discovery

## 📝 What You Need to Update

### 1. Terraform Variables

**REMOVED** (no longer needed):
- `key_name` - EC2 key pair name
- `allowed_ssh_cidr` - SSH access CIDR blocks

**KEPT** (still required):
- `aws_region`
- `project_name`
- `environment`
- `vpc_cidr`, `public_subnet_cidr`, `private_subnet_cidr`
- `instance_type`
- `github_repo_url`
- `github_runner_name`
- `github_runner_labels`

### 2. GitHub Secrets

**REMOVED** (no longer needed):
- `EC2_KEY_NAME`
- `ALLOWED_SSH_CIDR`

**REQUIRED** (still needed):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `PAT_TOKEN` (for GitHub runner registration)
- `TERRAFORM_STATE_BUCKET` (optional - created automatically)
- `TERRAFORM_LOCK_TABLE` (optional - created automatically)

### 3. Terraform Files Updated

- `terraform/variables.tf` - Removed SSH-related variables
- `terraform/main.tf` - Removed SSH parameter passing
- `terraform/modules/security/main.tf` - Removed SSH ingress rule
- `terraform/modules/ec2/main.tf` - Removed key_name reference
- `terraform/modules/ec2/user-data.sh` - Enhanced with Docker-based Nginx
- `.github/workflows/deploy-aws-infrastructure.yml` - Removed SSH references

## 🚀 How to Deploy Services

### Method 1: Direct Docker Run

```bash
# Deploy your service on the app-network
docker run -d \
  --name my-api \
  --network app-network \
  -p 8080:8080 \
  my-api:latest
```

### Method 2: Docker Compose

```yaml
version: '3.8'

services:
  api:
    image: my-api:latest
    container_name: my-api
    networks:
      - app-network
    ports:
      - "8080:8080"

networks:
  app-network:
    external: true
```

### Method 3: Via GitHub Actions Runner

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, aws, linux]
    steps:
      - name: Deploy Service
        run: |
          docker run -d \
            --name my-service \
            --network app-network \
            my-service:latest
```

## 🔧 Configuring Nginx for Your Services

### Quick Setup

1. **Deploy your service** (as shown above)

2. **Create Nginx config** at `/opt/nginx/conf.d/my-service.conf`:
   ```nginx
   upstream my_service {
       server my-service:8080;  # Use container name
   }
   
   server {
       listen 80;
       server_name _;
       
       location /my-service/ {
           proxy_pass http://my_service/;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }
   ```

3. **Reload Nginx**:
   ```bash
   docker exec nginx nginx -s reload
   ```

4. **Access your service**:
   ```bash
   curl http://<ec2-public-ip>/my-service/health
   ```

### Examples

#### Path-Based Routing
```nginx
# /api → api-service:8080
# /web → web-service:3000
# /metrics → metrics:9090

location /api/ {
    proxy_pass http://api-service:8080/;
}

location /web/ {
    proxy_pass http://web-service:3000/;
}
```

#### Host-Based Routing
```nginx
# api.example.com → api-service
# admin.example.com → admin-service

server {
    server_name api.example.com;
    location / {
        proxy_pass http://api-service:8080;
    }
}
```

For complete examples and patterns, see: [NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md)

## 🔐 Accessing the EC2 Instance

### Option 1: AWS Systems Manager (Recommended)

**Via AWS Console:**
1. Go to EC2 → Instances
2. Select your instance
3. Click "Connect" → "Session Manager" → "Connect"

**Via AWS CLI:**
```bash
# Start interactive session
aws ssm start-session --target i-1234567890abcdef0

# Run one-off commands
aws ssm send-command \
  --instance-ids i-1234567890abcdef0 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker ps"]'
```

### Option 2: GitHub Actions Runner

Deploy a workflow that runs commands on the self-hosted runner:

```yaml
jobs:
  manage:
    runs-on: [self-hosted, aws, linux]
    steps:
      - name: Check services
        run: docker ps
```

### Option 3: User Data / CloudInit

For initial setup, configurations are handled automatically via user-data script.

## 📊 Monitoring & Debugging

### Check Nginx Status
```bash
docker logs nginx
docker exec nginx nginx -t  # Test configuration
```

### Check Services
```bash
docker ps                           # List running containers
docker network inspect app-network  # View network members
```

### View Nginx Configuration
```bash
docker exec nginx cat /etc/nginx/nginx.conf
docker exec nginx ls /etc/nginx/conf.d/
```

## 🎯 Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **SSH Access** | Required key pair, open port 22 | No SSH, no keys needed |
| **Nginx** | Installed on OS | Docker container |
| **Service Routing** | Static configuration | Dynamic Docker DNS |
| **Configuration** | Manual file editing | Drop-in config files |
| **Security** | SSH attack surface | Completely isolated |
| **Management** | Direct SSH | AWS SSM or GitHub Actions |
| **Secrets** | 5 required | 3 required |

## 🔄 Migration Guide

If you have an existing deployment:

1. **Update your terraform.tfvars**:
   ```bash
   # Remove these lines:
   # key_name = "..."
   # allowed_ssh_cidr = [...]
   ```

2. **Update GitHub Secrets**:
   - Remove `EC2_KEY_NAME`
   - Remove `ALLOWED_SSH_CIDR`

3. **Pull latest changes**:
   ```bash
   git pull origin main
   ```

4. **Redeploy**:
   ```bash
   # Via GitHub Actions workflow, or:
   cd infrastructure/AWS/terraform
   terraform plan
   terraform apply
   ```

5. **Update service configs**:
   - Ensure services join `app-network`
   - Add Nginx configurations as needed

## 📚 Additional Resources

- [NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md) - Complete Nginx setup guide
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed architecture documentation
- [QUICKSTART.md](./QUICKSTART.md) - Fast deployment guide
- [README.md](./README.md) - Main documentation

## ❓ FAQ

**Q: How do I access the EC2 instance now?**  
A: Use AWS Systems Manager Session Manager (no SSH required) or run commands via the GitHub Actions runner.

**Q: How do services become accessible through Nginx?**  
A: Deploy services on the `app-network` Docker network and add a configuration file to `/opt/nginx/conf.d/`.

**Q: Can I still use docker-compose?**  
A: Yes! Just ensure your services use the external network `app-network`.

**Q: What if I need SSH for debugging?**  
A: Use AWS Systems Manager Session Manager instead - it provides shell access without opening SSH ports.

**Q: How do I add SSL/HTTPS?**  
A: Mount certificates in the Nginx container and update the configuration. See [NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md) for examples.

**Q: Can I run multiple services?**  
A: Yes! Each service gets its own Nginx config file in `/opt/nginx/conf.d/`.

## 🛟 Support

For issues or questions:
1. Check [NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md) for routing examples
2. Review [ARCHITECTURE.md](./ARCHITECTURE.md) for infrastructure details
3. Check Nginx logs: `docker logs nginx`
4. Verify Docker network: `docker network inspect app-network`
