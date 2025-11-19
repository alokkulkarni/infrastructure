# Azure Infrastructure Architecture

## Overview

This document describes the Azure infrastructure architecture with public/private subnet design, enabling secure deployment of containerized applications accessible from the internet via Nginx reverse proxy.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ HTTP/HTTPS (80/443)
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Public IP (VM)                                 │
│                   xx.xx.xx.xx                                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │
┌────────────────────────┴────────────────────────────────────────┐
│                    Virtual Network (10.0.0.0/16)                │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Public Subnet (10.0.1.0/24)                           │    │
│  │  - Reserved for future load balancers                  │    │
│  │  - Application Gateway                                 │    │
│  │  - Azure Firewall                                      │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Private Subnet (10.0.2.0/24)                          │    │
│  │  ┌──────────────────────────────────────────────┐      │    │
│  │  │  VM with Public IP                           │      │    │
│  │  │  Private IP: 10.0.2.x                        │      │    │
│  │  │  Public IP: Assigned                         │      │    │
│  │  │                                              │      │    │
│  │  │  ┌────────────────────────────────┐         │      │    │
│  │  │  │  Nginx Container (Reverse      │         │      │    │
│  │  │  │  Proxy) - Ports 80/443         │         │      │    │
│  │  │  └────────────┬───────────────────┘         │      │    │
│  │  │               │                              │      │    │
│  │  │               │ Docker Network (app-network) │      │    │
│  │  │               │                              │      │    │
│  │  │  ┌────────────┴───────────────────┐         │      │    │
│  │  │  │  Application Containers        │         │      │    │
│  │  │  │  - Backend Services            │         │      │    │
│  │  │  │  - Databases                   │         │      │    │
│  │  │  │  - Other Services              │         │      │    │
│  │  │  └────────────────────────────────┘         │      │    │
│  │  │                                              │      │    │
│  │  │  ┌────────────────────────────────┐         │      │    │
│  │  │  │  GitHub Actions Runner         │         │      │    │
│  │  │  └────────────────────────────────┘         │      │    │
│  │  └──────────────────────────────────────────────┘      │    │
│  │                                                          │    │
│  │  NSG: Allow HTTP/HTTPS inbound, All outbound           │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  NAT Gateway (for private subnet outbound)            │    │
│  │  Public IP: xx.xx.xx.xx                                │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

### Inbound Traffic (User → Application)

```
Internet User
    ↓ (HTTP/HTTPS)
VM Public IP (NSG allows 80/443)
    ↓
VM Network Interface (10.0.2.x)
    ↓
Nginx Docker Container (80/443)
    ↓ (proxy_pass)
Application Container on app-network (8080)
    ↓
Application Response
    ↓
Back to User
```

### Outbound Traffic (VM → Internet)

```
VM in Private Subnet (10.0.2.x)
    ↓
NAT Gateway
    ↓
NAT Public IP
    ↓
Internet (package downloads, API calls, etc.)
```

## Components

### 1. Virtual Network (VNet)
- **Address Space**: 10.0.0.0/16
- **Purpose**: Isolated network for all Azure resources
- **DNS**: Azure-provided DNS

### 2. Public Subnet
- **Address Space**: 10.0.1.0/24
- **Purpose**: Reserved for future internet-facing resources
- **Use Cases**:
  - Azure Load Balancer
  - Application Gateway (for SSL termination, WAF)
  - Azure Firewall
  - Bastion Host

### 3. Private Subnet
- **Address Space**: 10.0.2.0/24
- **Purpose**: Backend resources (VMs, databases)
- **Outbound**: Via NAT Gateway
- **Security**: Protected by NSG

### 4. NAT Gateway
- **Purpose**: Provides outbound internet connectivity for private subnet
- **Public IP**: Static IP for outbound traffic
- **Use Cases**:
  - Package installation (apt, docker pull)
  - API calls to external services
  - GitHub runner registration

### 5. Network Security Group (NSG)
- **Applied To**: Private subnet
- **Inbound Rules**:
  - Allow HTTP (80) from Internet
  - Allow HTTPS (443) from Internet
  - Deny SSH (22) - No SSH access
- **Outbound Rules**:
  - Allow all (for package installation and updates)

### 6. Virtual Machine
- **OS**: Ubuntu 22.04 LTS
- **Size**: Standard_D2s_v3 (2 vCPU, 8 GB RAM)
- **Network**: Private subnet with public IP attached
- **Identity**: System-assigned managed identity
- **SSH**: Disabled password authentication, no SSH access via NSG

#### VM Components:
- **Docker Engine**: Container runtime
- **Docker Compose**: Multi-container orchestration
- **Nginx Container**: Reverse proxy (ports 80/443)
- **GitHub Actions Runner**: Self-hosted CI/CD runner
- **Docker Network**: app-network (bridge) for container communication

### 7. Key Vault
- **Purpose**: Secure storage for SSH private key (backup only)
- **Access**: Via managed identity
- **Soft Delete**: Enabled (7 days retention)

### 8. Public IPs

#### VM Public IP
- **Type**: Static
- **SKU**: Standard
- **Purpose**: Direct internet access to VM for application traffic
- **DNS**: Optional (can assign DNS label)

#### NAT Gateway Public IP
- **Type**: Static
- **SKU**: Standard
- **Purpose**: Outbound traffic from private subnet

## Security Architecture

### Defense in Depth

1. **Network Layer**
   - Public/Private subnet separation
   - NSG rules (HTTP/HTTPS only inbound)
   - No SSH access from internet
   - NAT Gateway for controlled outbound

2. **VM Layer**
   - Ubuntu 22.04 with security updates
   - Disabled password authentication
   - System-assigned managed identity
   - No public SSH key access

3. **Application Layer**
   - Docker container isolation
   - Nginx reverse proxy (rate limiting, header filtering)
   - Separate Docker network for containers
   - No direct container port exposure

4. **Identity Layer**
   - Managed identities for Azure resource access
   - Azure AD OIDC for GitHub Actions
   - Key Vault for secret storage
   - No long-lived credentials

### Access Methods

**For Applications (Users):**
- ✅ HTTP/HTTPS via public IP → Nginx → Docker containers
- ✅ Custom domain (configure DNS to point to VM public IP)

**For Administration:**
- ✅ Azure Serial Console
- ✅ Azure `az vm run-command`
- ✅ Azure Bastion (if deployed)
- ❌ SSH (intentionally blocked)

## Application Deployment Flow

### 1. Deploy Container Application

```bash
# SSH to VM via Azure Serial Console or run-command
docker run -d \
  --name my-backend \
  --network app-network \
  -e DATABASE_URL=postgres://... \
  my-backend:latest
```

### 2. Configure Nginx Reverse Proxy

```bash
cat > /opt/nginx/conf.d/my-backend.conf <<EOF
server {
    listen 80;
    server_name api.example.com;
    
    location / {
        proxy_pass http://my-backend:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Reload Nginx
docker exec nginx nginx -s reload
```

### 3. Access Application

- **Via Public IP**: `http://VM_PUBLIC_IP`
- **Via Domain**: `http://api.example.com` (configure DNS)

### Using Docker Compose

```yaml
version: '3.8'

services:
  backend:
    image: my-backend:latest
    networks:
      - app-network
    environment:
      - DB_HOST=postgres
      - REDIS_HOST=redis
  
  postgres:
    image: postgres:15
    networks:
      - app-network
    volumes:
      - postgres-data:/var/lib/postgresql/data
  
  redis:
    image: redis:alpine
    networks:
      - app-network

networks:
  app-network:
    external: true

volumes:
  postgres-data:
```

Deploy:
```bash
docker compose up -d
```

## Scaling Considerations

### Current Setup (Single VM)
- ✅ Simple deployment
- ✅ Low cost
- ✅ Good for development/staging
- ⚠️ Single point of failure
- ⚠️ Limited horizontal scaling

### Future Enhancements

#### Option 1: Multiple VMs with Load Balancer
```
Internet → Azure Load Balancer (Public Subnet)
              ↓
         [VM1, VM2, VM3] (Private Subnet)
              ↓
         Docker Containers
```

#### Option 2: Azure Container Instances
```
Internet → Application Gateway (Public Subnet)
              ↓
         Azure Container Instances (Private Subnet)
```

#### Option 3: Azure Kubernetes Service (AKS)
```
Internet → Application Gateway (Public Subnet)
              ↓
         AKS Cluster (Private Subnet)
              ↓
         Kubernetes Pods
```

## Cost Breakdown (Monthly Estimates)

| Resource | Specification | Estimated Cost |
|----------|--------------|----------------|
| VM | Standard_D2s_v3 | ~$70 |
| Managed Disk | 30 GB Premium SSD | ~$5 |
| VM Public IP | Static Standard | ~$3.60 |
| NAT Gateway | Standard + 5GB data | ~$35 |
| NAT Public IP | Static Standard | ~$3.60 |
| Storage Account | State backend | ~$1 |
| Key Vault | Standard tier | ~$0.30 |
| Virtual Network | Standard | Free |
| NSG | Standard | Free |
| **Total** | | **~$118/month** |

**Note**: Costs vary by region. NAT Gateway includes ~$0.045/GB data processed.

## High Availability Options

### 1. Availability Zones
- Deploy VMs across zones
- Zone-redundant Load Balancer
- Zone-redundant Public IPs

### 2. Availability Sets
- Multiple VMs in same region
- Fault domain separation
- Update domain separation

### 3. Azure Site Recovery
- VM replication to secondary region
- Automated failover
- Disaster recovery

## Monitoring and Diagnostics

### 1. Azure Monitor
- VM metrics (CPU, memory, disk, network)
- Boot diagnostics
- Performance counters

### 2. Log Analytics
- Docker container logs
- Nginx access/error logs
- Application logs

### 3. Network Watcher
- NSG flow logs
- Connection monitor
- Packet capture

### 4. Application Insights
- Application performance monitoring
- Request tracking
- Dependency tracking

## Best Practices

### Security
1. ✅ Use NSG to restrict inbound traffic
2. ✅ No SSH access from internet
3. ✅ System-assigned managed identities
4. ✅ Secrets in Key Vault
5. ✅ Regular security updates via cloud-init
6. ⚠️ Consider Azure Firewall for advanced filtering
7. ⚠️ Enable Azure DDoS Protection Standard for production

### Networking
1. ✅ Public/Private subnet separation
2. ✅ NAT Gateway for outbound
3. ✅ Static public IPs
4. ⚠️ Consider Azure Bastion for admin access
5. ⚠️ Use Application Gateway for SSL termination
6. ⚠️ Implement WAF (Web Application Firewall)

### Deployment
1. ✅ Infrastructure as Code (Terraform)
2. ✅ OIDC authentication (no secrets)
3. ✅ GitHub Actions for CI/CD
4. ✅ Docker containers for applications
5. ✅ Nginx reverse proxy
6. ⚠️ Blue-green deployments for zero downtime
7. ⚠️ Automated backups

### Cost Optimization
1. ⚠️ Use Azure Reserved Instances (1-3 year)
2. ⚠️ Implement auto-shutdown for dev/test
3. ⚠️ Right-size VMs based on usage
4. ⚠️ Use Azure Spot VMs for non-critical workloads
5. ⚠️ Monitor NAT Gateway data processing costs

## Deployment Checklist

- [ ] Run backend setup script (Storage Account)
- [ ] Configure Azure AD application for OIDC
- [ ] Add GitHub Secrets (CLIENT_ID, TENANT_ID, SUBSCRIPTION_ID)
- [ ] Deploy infrastructure via GitHub Actions
- [ ] Verify VM public IP is assigned
- [ ] Test HTTP access to public IP
- [ ] Deploy sample container application
- [ ] Configure Nginx reverse proxy
- [ ] Test application access via public IP
- [ ] (Optional) Configure custom domain DNS
- [ ] Enable monitoring and alerts
- [ ] Document application-specific configs

## Troubleshooting

### Cannot Access Application via Public IP

1. **Check NSG rules**: Ensure HTTP/HTTPS allowed
   ```bash
   az network nsg rule list --nsg-name <NSG_NAME> --resource-group <RG_NAME>
   ```

2. **Verify Nginx is running**:
   ```bash
   az vm run-command invoke \
     --name <VM_NAME> \
     --resource-group <RG_NAME> \
     --command-id RunShellScript \
     --scripts "docker ps | grep nginx"
   ```

3. **Check application container**:
   ```bash
   az vm run-command invoke \
     --name <VM_NAME> \
     --resource-group <RG_NAME> \
     --command-id RunShellScript \
     --scripts "docker ps"
   ```

4. **Test Nginx config**:
   ```bash
   docker exec nginx nginx -t
   ```

### NAT Gateway Issues

1. **Verify NAT Gateway association**:
   ```bash
   az network vnet subnet show \
     --name <SUBNET_NAME> \
     --vnet-name <VNET_NAME> \
     --resource-group <RG_NAME> \
     --query natGateway
   ```

2. **Check outbound connectivity**:
   ```bash
   az vm run-command invoke \
     --name <VM_NAME> \
     --resource-group <RG_NAME> \
     --command-id RunShellScript \
     --scripts "curl -I https://google.com"
   ```

## Summary

This Azure infrastructure provides:

- ✅ **Public/Private Subnet Architecture**: Proper network segmentation
- ✅ **Public IP Access**: Users can access applications from internet
- ✅ **Nginx Reverse Proxy**: Running as Docker container
- ✅ **Docker Engine**: Installed and configured
- ✅ **Docker Compose**: Available for multi-container apps
- ✅ **GitHub Actions Runner**: Self-hosted runner on VM
- ✅ **Secure by Default**: No SSH, NSG protection, managed identities
- ✅ **Scalable Foundation**: Ready for load balancers and multiple VMs
- ✅ **OIDC Authentication**: No credential management

**Access Pattern**: Internet → VM Public IP → Nginx Container → Application Containers

Users can access applications deployed on the Docker engine through the Nginx reverse proxy using the VM's public IP address.
