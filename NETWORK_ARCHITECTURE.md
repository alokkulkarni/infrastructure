# Network Architecture: AWS & Azure Comparison

## Overview

This document explains the network architecture for both AWS and Azure deployments, focusing on how public/private subnets, internet gateways, load balancers, and compute resources interact to provide secure and accessible application hosting.

---

## AWS Network Architecture

### Architecture Diagram (Conceptual)

```
                                    Internet
                                       ↓
                              [Internet Gateway]
                                       ↓
                    ┌─────────────────────────────────┐
                    │         VPC (10.0.0.0/16)       │
                    │                                 │
                    │  ┌──────────────────────────┐  │
                    │  │  Public Subnet 1         │  │
                    │  │  (10.0.1.0/24)           │  │
                    │  │  AZ: us-east-1a          │  │
                    │  │                          │  │
                    │  │  ┌───────────────────┐  │  │
                    │  │  │  Application      │  │  │
                    │  │  │  Load Balancer    │◄─┼──┼──── HTTP/HTTPS (Port 80/443)
                    │  │  │  (Public IP)      │  │  │     from Internet (0.0.0.0/0)
                    │  │  └─────────┬─────────┘  │  │
                    │  └────────────┼─────────────┘  │
                    │               │                 │
                    │  ┌──────────────────────────┐  │
                    │  │  Public Subnet 2         │  │
                    │  │  (10.0.3.0/24)           │  │
                    │  │  AZ: us-east-1b          │  │
                    │  │  (ALB multi-AZ req)      │  │
                    │  └──────────────────────────┘  │
                    │               │                 │
                    │  ┌──────────────────────────┐  │
                    │  │  Public Subnet (NAT)     │  │
                    │  │  [NAT Gateway + EIP]     │  │
                    │  └────────────┬─────────────┘  │
                    │               │                 │
                    │               ↓ (forwards to)   │
                    │  ┌──────────────────────────┐  │
                    │  │  Private Subnet          │  │
                    │  │  (10.0.2.0/24)           │  │
                    │  │  AZ: us-east-1a          │  │
                    │  │                          │  │
                    │  │  ┌───────────────────┐  │  │
                    │  │  │  EC2 Instance     │  │  │
                    │  │  │  - Docker         │  │  │
                    │  │  │  - Nginx Proxy    │  │  │
                    │  │  │  - GitHub Runner  │  │  │
                    │  │  │  (Private IP only)│  │  │
                    │  │  └───────────────────┘  │  │
                    │  │           ↓              │  │
                    │  └───────────┼──────────────┘  │
                    │              ↓                  │
                    │     [NAT Gateway] → Internet    │
                    │    (Outbound only)              │
                    └─────────────────────────────────┘
```

### Components Explanation

#### 1. **VPC (Virtual Private Cloud)**
- **CIDR**: `10.0.0.0/16`
- Provides isolated network space for all resources
- Enables DNS hostname and DNS support for service discovery

#### 2. **Internet Gateway (IGW)**
- Attached to VPC
- Provides route to/from internet for public subnets
- Enables inbound internet traffic to ALB
- No direct attachment to EC2 instances

#### 3. **Public Subnets (2 required for ALB)**
- **Subnet 1**: `10.0.1.0/24` in `us-east-1a`
- **Subnet 2**: `10.0.3.0/24` in `us-east-1b`
- Route table: `0.0.0.0/0` → Internet Gateway
- Auto-assign public IPs enabled
- Hosts: Application Load Balancer (spans both AZs)

#### 4. **Application Load Balancer (ALB)**
- **Type**: Public-facing (internet-facing)
- **Subnets**: Deployed across 2 public subnets (multi-AZ for HA)
- **Security Group**: Allows HTTP/HTTPS from `0.0.0.0/0`
- **Target**: EC2 instance in private subnet
- **Health Check**: `GET /health` every 30s
- **Features**:
  - Automatic DNS name (no need for Elastic IP)
  - Layer 7 load balancing
  - SSL/TLS termination (when certificate configured)
  - Path-based and host-based routing

#### 5. **Private Subnet**
- **CIDR**: `10.0.2.0/24` in `us-east-1a`
- Route table: `0.0.0.0/0` → NAT Gateway
- No public IP assignment
- Hosts: EC2 instance with applications

#### 6. **EC2 Instance (Private)**
- **Location**: Private subnet
- **IP**: Private IP only (e.g., `10.0.2.x`)
- **Access**: Only via ALB, no direct internet access
- **Security Group**: Allows HTTP (port 80) from ALB security group only
- **Outbound**: Via NAT Gateway for:
  - GitHub Actions runner connectivity
  - Docker image pulls
  - Package updates
  - External API calls

#### 7. **NAT Gateway**
- **Location**: Public subnet
- **Elastic IP**: Static public IP attached
- **Purpose**: Enables outbound internet for private subnet
- **Traffic**: One-way (outbound only from private subnet)

#### 8. **Security Groups**

**ALB Security Group:**
- Inbound: HTTP (80) and HTTPS (443) from `0.0.0.0/0`
- Outbound: All traffic

**EC2 Security Group:**
- Inbound: HTTP (80) from ALB security group **only**
- Outbound: All traffic (for GitHub, Docker, updates)

### Traffic Flow

#### Inbound (User → Application):
```
Internet User (HTTP/HTTPS)
    ↓
Internet Gateway
    ↓
Application Load Balancer (Public Subnets)
    ↓
EC2 Instance (Private Subnet) - Port 80
    ↓
Nginx Reverse Proxy
    ↓
Docker Containers (on app-network)
```

#### Outbound (Application → Internet):
```
EC2 Instance (Private Subnet)
    ↓
NAT Gateway (Public Subnet)
    ↓
Internet Gateway
    ↓
Internet (GitHub, Docker Hub, apt repos)
```

### Key Benefits
- **Security**: EC2 has no public IP, cannot be directly accessed
- **High Availability**: ALB spans 2 AZs
- **Scalability**: Can add more EC2 instances to target group
- **Monitoring**: ALB provides connection metrics and logs
- **Cost-Effective**: Single NAT Gateway for all private resources

---

## Azure Network Architecture

### Architecture Diagram (Conceptual)

```
                                    Internet
                                       ↓
                    ┌─────────────────────────────────┐
                    │      VNet (10.0.0.0/16)         │
                    │                                 │
                    │  ┌──────────────────────────┐  │
                    │  │  Public Subnet           │  │
                    │  │  (10.0.1.0/24)           │  │
                    │  │                          │  │
                    │  │  [Reserved for future    │  │
                    │  │   Load Balancers/        │  │
                    │  │   App Gateways]          │  │
                    │  └──────────────────────────┘  │
                    │                                 │
                    │  ┌──────────────────────────┐  │
                    │  │  NAT Gateway             │  │
                    │  │  (Public IP attached)    │  │
                    │  └────────────┬─────────────┘  │
                    │               │                 │
                    │               ↓                 │
                    │  ┌──────────────────────────┐  │
                    │  │  Private Subnet          │  │
                    │  │  (10.0.2.0/24)           │  │
                    │  │                          │  │
                    │  │  ┌───────────────────┐  │  │
                    │  │  │  Virtual Machine  │◄─┼──┼──── HTTP/HTTPS (Port 80/443)
                    │  │  │  - Docker         │  │  │     from Internet (0.0.0.0/0)
                    │  │  │  - Nginx Proxy    │  │  │     via VM's Public IP
                    │  │  │  - GitHub Runner  │  │  │
                    │  │  │                   │  │  │
                    │  │  │  [Public IP]      │  │  │
                    │  │  │  [Private IP]     │  │  │
                    │  │  └─────────┬─────────┘  │  │
                    │  │            ↓             │  │
                    │  └────────────┼─────────────┘  │
                    │               ↓                 │
                    │     [NAT Gateway] → Internet    │
                    │    (Backup outbound route)      │
                    └─────────────────────────────────┘
```

### Components Explanation

#### 1. **Virtual Network (VNet)**
- **Address Space**: `10.0.0.0/16`
- Azure's equivalent to AWS VPC
- Provides network isolation and segmentation

#### 2. **Public Subnet**
- **CIDR**: `10.0.1.0/24`
- Reserved for future internet-facing resources
- Currently unused but available for:
  - Azure Load Balancer
  - Azure Application Gateway
  - Bastion hosts

#### 3. **Private Subnet**
- **CIDR**: `10.0.2.0/24`
- Hosts the Virtual Machine
- Associated with NAT Gateway for outbound connectivity

#### 4. **Virtual Machine (with Public IP)**
- **Location**: Private subnet
- **IPs**:
  - **Private IP**: `10.0.2.x` (internal communication)
  - **Public IP**: Static public IP directly attached to NIC
- **Network Interface**: Bridge between VM and subnet
- **Access**: 
  - Inbound: Direct via Public IP (filtered by NSG)
  - Outbound: Via NAT Gateway (preferred) or Public IP
- **Features**:
  - Managed Identity (SystemAssigned) for Azure service access
  - No SSH password (key-based only, but not used)
  - Cloud-init for automated setup

#### 5. **Public IP (VM)**
- **Allocation**: Static
- **SKU**: Standard (required for NAT Gateway compatibility)
- **Purpose**: Direct inbound access to VM for nginx
- **Attachment**: Network Interface → VM

#### 6. **NAT Gateway**
- **Public IP**: Separate static public IP
- **Purpose**: Preferred outbound route for private subnet
- **Benefits**:
  - Consistent outbound IP
  - Better for scaling (multiple VMs can share)
  - Separates inbound and outbound traffic

#### 7. **Network Security Group (NSG)**
- Applied to private subnet
- **Inbound Rules**:
  - Priority 100: Allow HTTP (80) from `0.0.0.0/0`
  - Priority 110: Allow HTTPS (443) from `0.0.0.0/0`
- **Outbound Rules**:
  - Priority 100: Allow all outbound traffic

### Traffic Flow

#### Inbound (User → Application):
```
Internet User (HTTP/HTTPS)
    ↓
VM Public IP (Static)
    ↓
Network Interface (NIC)
    ↓
Network Security Group (NSG filters)
    ↓
Virtual Machine (Private Subnet)
    ↓
Nginx Reverse Proxy (Port 80)
    ↓
Docker Containers (on app-network)
```

#### Outbound (Application → Internet):
```
Virtual Machine
    ↓
NAT Gateway (Preferred route)
    ↓
Internet (GitHub, Docker Hub, apt repos)
```

### Key Differences from AWS
- **Direct Public IP**: VM has public IP attached, unlike AWS EC2 in private subnet
- **No Load Balancer**: Direct access, simpler architecture for single VM
- **NSG vs Security Group**: NSG can be applied to subnet or NIC, AWS SG only to instances
- **NAT Gateway**: Used for consistent outbound IP, not strictly required (VM has public IP)

### Future Enhancements (Optional)
To match AWS architecture with load balancer:
1. Remove public IP from VM
2. Deploy Azure Load Balancer in public subnet
3. Configure backend pool with VM
4. Update NSG to allow traffic from Load Balancer only

---

## Comparison Summary

| Aspect | AWS | Azure |
|--------|-----|-------|
| **Ingress Path** | Internet → IGW → ALB (public) → EC2 (private) | Internet → Public IP → VM (private subnet) |
| **Public IP** | ALB has public IP (DNS name) | VM has public IP directly attached |
| **Load Balancer** | Application Load Balancer (required) | None (direct access) |
| **Multi-AZ** | Yes (ALB spans 2 AZs) | Single VM (no LB) |
| **Outbound** | Via NAT Gateway | Via NAT Gateway (preferred) or Public IP |
| **Security** | EC2 not directly accessible | VM directly accessible (NSG protected) |
| **Complexity** | Higher (ALB + 2 public subnets) | Lower (direct attachment) |
| **Scaling** | Easy (add targets to ALB) | Requires Load Balancer addition |

---

## Terraform Outputs

### AWS Outputs
After successful deployment, Terraform outputs:

```hcl
nginx_url              = "http://<alb-dns-name>.elb.amazonaws.com"
nginx_health_check     = "http://<alb-dns-name>.elb.amazonaws.com/health"
alb_dns_name          = "<project>-<env>-alb-<id>.us-east-1.elb.amazonaws.com"
ec2_private_ip        = "10.0.2.x"
nat_gateway_public_ip = "x.x.x.x" (NAT Gateway IP)
```

**Access URL**: Use the `nginx_url` output to access deployed applications

### Azure Outputs
After successful deployment, Terraform outputs:

```hcl
nginx_url              = "http://<vm-public-ip>"
nginx_health_check     = "http://<vm-public-ip>/health"
vm_public_ip          = "x.x.x.x" (VM's public IP)
vm_private_ip         = "10.0.2.x"
nat_gateway_public_ip = "x.x.x.x" (NAT Gateway IP)
```

**Access URL**: Use the `nginx_url` output to access deployed applications

---

## Accessing Nginx Reverse Proxy

Both architectures deploy a Docker-based Nginx reverse proxy with automatic configuration:

### Default Endpoints
- **Root**: `http://<url>/` - Shows "Nginx reverse proxy is running" message
- **Health Check**: `http://<url>/health` - Returns "healthy" (used by ALB health checks in AWS)

### Deploying Applications
Applications deployed on the `app-network` Docker network are automatically configured:

```bash
docker run -d \
  --name my-app \
  --network app-network \
  --label nginx.enable=true \
  --label nginx.path=/api \
  --label nginx.port=8080 \
  my-app:latest
```

**Access**: `http://<url>/api` → routes to container `my-app:8080`

### Docker Labels for Auto-Configuration
- `nginx.enable`: Enable/disable auto-config (default: true)
- `nginx.host`: Server name for host-based routing
- `nginx.path`: URL path prefix (default: /container-name)
- `nginx.port`: Backend port (auto-detected if not specified)

---

## Security Considerations

### AWS
1. ✅ EC2 has no public IP (cannot be directly accessed)
2. ✅ ALB provides DDoS protection and security features
3. ✅ Security groups use least-privilege (ALB → EC2 only)
4. ✅ Private subnet for compute, public for load balancing
5. ✅ NAT Gateway for controlled outbound access
6. ⚠️  Consider: AWS WAF on ALB for web application firewall
7. ⚠️  Consider: ALB access logs for security auditing

### Azure
1. ⚠️  VM has public IP (directly accessible from internet)
2. ✅ NSG provides firewall protection
3. ✅ No SSH password authentication
4. ✅ Managed Identity for Azure service access
5. ✅ NAT Gateway for consistent outbound IP
6. ⚠️  Consider: Azure DDoS Protection Standard
7. ⚠️  Consider: Azure Firewall for advanced threat protection
8. 🔧 **Recommendation**: Add Azure Load Balancer for production (remove public IP from VM)

---

## Cost Optimization

### AWS
- **NAT Gateway**: ~$33/month + data transfer
- **ALB**: ~$22/month + LCU charges
- **EC2**: Based on instance type (t3.medium ~$30/month)
- **Total**: ~$85-100/month base cost

**Optimization Tips**:
- Use NAT Instance instead of NAT Gateway for dev ($5-10/month)
- Use single-AZ for non-production (1 public subnet)
- Schedule EC2 stop/start for dev environments

### Azure
- **NAT Gateway**: ~$33/month + data transfer
- **Public IP**: ~$3-5/month (Static)
- **VM**: Based on size (Standard_D2s_v3 ~$70/month)
- **Total**: ~$106-110/month base cost

**Optimization Tips**:
- Use Azure Bastion instead of public IP for access ($5/month)
- Deallocate VMs when not in use (stops compute charges)
- Use Spot VMs for dev workloads (up to 90% savings)

---

## Troubleshooting

### AWS - Cannot Access Application

1. **Check ALB Health**:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <arn>
   ```

2. **Verify Security Groups**:
   - ALB SG: Allows 80/443 from 0.0.0.0/0
   - EC2 SG: Allows 80 from ALB SG

3. **Test from EC2**:
   ```bash
   curl http://localhost/health  # Should return "healthy"
   ```

4. **Check ALB DNS Resolution**:
   ```bash
   nslookup <alb-dns-name>
   ```

### Azure - Cannot Access Application

1. **Verify Public IP**:
   ```bash
   az network public-ip show --name <name> --resource-group <rg>
   ```

2. **Check NSG Rules**:
   ```bash
   az network nsg rule list --nsg-name <nsg> --resource-group <rg>
   ```

3. **Test from VM** (using Azure Serial Console or Run Command):
   ```bash
   curl http://localhost/health  # Should return "healthy"
   ```

4. **Check VM Status**:
   ```bash
   az vm get-instance-view --name <name> --resource-group <rg>
   ```

---

## References

### AWS Documentation
- [VPC with Public and Private Subnets](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)

### Azure Documentation
- [Virtual Network Overview](https://docs.microsoft.com/azure/virtual-network/virtual-networks-overview)
- [NAT Gateway](https://docs.microsoft.com/azure/virtual-network/nat-gateway/nat-overview)
- [Network Security Groups](https://docs.microsoft.com/azure/virtual-network/network-security-groups-overview)

---

**Last Updated**: 2025-11-20
**Version**: 2.0
