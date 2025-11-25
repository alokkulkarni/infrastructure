# Azure Load Balancer Architecture

## Overview

This infrastructure uses an Azure Standard Load Balancer to enable inbound internet traffic to VMs hosted in private subnets while maintaining security through NAT Gateway for outbound connections.

## Architecture Components

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│  Public Subnet (10.0.1.0/24)       │
│  ┌──────────────────────────────┐  │
│  │  Azure Load Balancer         │  │
│  │  - Public IP: <LB-IP>        │  │
│  │  - Frontend: Port 80, 443    │  │
│  │  - Health Probe: HTTP/80     │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
             │
             │ (Internal routing)
             ▼
┌─────────────────────────────────────┐
│  Private Subnet (10.0.2.0/24)      │
│  ┌──────────────────────────────┐  │
│  │  VM (GitHub Runner)          │  │
│  │  - Private IP: 10.0.2.x      │  │
│  │  - Nginx on port 80, 443     │  │
│  │  - Docker containers         │  │
│  │  - Backend pool member       │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  NAT Gateway                 │  │
│  │  - Outbound internet only    │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
             │
             ▼
         Internet (Outbound)
```

## Traffic Flow

### Inbound Traffic (Internet → VM)
1. **Client Request**: External client sends HTTP/HTTPS request to Load Balancer public IP
2. **Load Balancer**: Receives traffic on public subnet, performs health check on backend
3. **Health Probe**: Periodically checks HTTP port 80 on VM (every 15 seconds)
4. **Load Balancing**: If healthy, forwards traffic to VM's private IP in backend pool
5. **VM Nginx**: Receives request and processes/proxies to Docker containers
6. **Response**: VM responds back through the same path

### Outbound Traffic (VM → Internet)
1. **VM Initiates**: VM in private subnet makes outbound connection (e.g., Docker pulls, GitHub API)
2. **NAT Gateway**: Routes all outbound traffic through NAT Gateway public IP
3. **Internet**: External services see requests from NAT Gateway IP
4. **Response**: Return traffic flows back through NAT Gateway to VM

## Key Benefits

### Security
- **Private VM**: VM has no direct public IP, reducing attack surface
- **NAT Gateway**: Outbound connections use dedicated IP (not exposed for inbound)
- **NSG Protection**: Network Security Groups filter traffic at subnet level
- **Least Privilege**: Separates inbound (LB) from outbound (NAT) paths

### Scalability
- **Easy Scaling**: Add more VMs to backend pool without changing architecture
- **Load Distribution**: Load Balancer distributes traffic across multiple VMs
- **Health-Based Routing**: Automatically removes unhealthy VMs from rotation

### High Availability
- **No Single Point of Failure**: Load Balancer is Azure-managed, highly available
- **Health Probes**: Automatic detection of VM failures
- **Zone Redundancy**: Standard SKU Load Balancer is zone-redundant by default

### Cost Efficiency
- **Standard SKU**: More cost-effective than Application Gateway for simple HTTP/HTTPS
- **Shared NAT Gateway**: Multiple VMs can share one NAT Gateway for outbound
- **No Data Transfer Charges**: Internal VNet traffic is free

## Component Details

### Azure Load Balancer (Standard SKU)
- **Location**: Public subnet
- **Public IP**: Static allocation, Standard SKU
- **Frontend Configuration**: Single public IP endpoint
- **Backend Pool**: Contains VM network interface
- **Health Probe**: HTTP probe on port 80, path `/`, interval 15s
- **Load Balancing Rules**:
  - HTTP: Port 80 → Port 80
  - HTTPS: Port 443 → Port 443
- **SNAT Disabled**: Uses NAT Gateway for outbound instead

### NAT Gateway
- **Location**: Associated with private subnet
- **Purpose**: Outbound internet connectivity only
- **Public IP**: Dedicated for outbound traffic
- **Benefit**: Consistent outbound IP for allow-listing

### Network Security Group (NSG)
- **Scope**: Attached to private subnet and VM NIC
- **Inbound Rules**:
  - Allow HTTP (80) from Load Balancer
  - Allow HTTPS (443) from Load Balancer
  - Deny all other inbound by default
- **Outbound Rules**:
  - Allow all (NAT Gateway controls egress)

## Why This Architecture?

### Problem: VM on Private Subnet with Public IP
The original setup had a VM in a private subnet with:
- Public IP directly attached to VM NIC
- NAT Gateway on the same subnet

**This configuration doesn't work** because:
- NAT Gateway is designed for outbound-only traffic
- Azure doesn't route inbound traffic to VMs on NAT Gateway subnets
- Public IP on VM becomes unreachable despite correct NSG rules

### Solution: Load Balancer in Public Subnet
By introducing a Load Balancer:
- ✅ Load Balancer sits in public subnet (no NAT Gateway conflict)
- ✅ VM stays in private subnet (maintains security)
- ✅ NAT Gateway handles all outbound traffic (consistent egress IP)
- ✅ Load Balancer handles all inbound traffic (health checks, distribution)
- ✅ VM has no direct public IP (reduced attack surface)

## Comparison with Alternatives

### vs. Public Subnet for VM
| Aspect | Load Balancer + Private Subnet | Public Subnet |
|--------|-------------------------------|---------------|
| Security | ✅ VM has no public IP | ❌ VM directly exposed |
| Scalability | ✅ Easy to add VMs | ❌ Each VM needs public IP |
| Outbound IP | ✅ Consistent NAT Gateway IP | ❌ Each VM has own IP |
| Cost | 💰 Load Balancer cost | 💰 Multiple public IPs |

### vs. Application Gateway
| Aspect | Load Balancer | Application Gateway |
|--------|---------------|---------------------|
| Cost | ✅ Lower cost (~$18/mo) | ❌ Higher cost (~$140/mo) |
| Features | ❌ Layer 4 (TCP) only | ✅ Layer 7 (HTTP), WAF, SSL |
| Complexity | ✅ Simple setup | ❌ More complex |
| Use Case | Simple HTTP/HTTPS | Web applications with WAF |

**For this use case**: Standard Load Balancer is ideal since:
- Nginx handles Layer 7 routing (don't need Application Gateway)
- Cost-effective for single VM (can scale to multiple)
- Simple deployment and management

## Access URLs

After deployment, use the Load Balancer public IP to access services:

```bash
# Get Load Balancer public IP from Terraform output
terraform output load_balancer_public_ip

# Access Nginx
curl http://<LB-PUBLIC-IP>

# Check health
curl http://<LB-PUBLIC-IP>/health

# Access Docker containers (proxied by Nginx)
curl http://<LB-PUBLIC-IP>/<container-path>
```

## Troubleshooting

### Load Balancer Health Probe Failing
```bash
# Check VM Nginx status
az vm run-command invoke \
  --resource-group <rg-name> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "systemctl status nginx"

# Check if port 80 is listening
az vm run-command invoke \
  --resource-group <rg-name> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "ss -tlnp | grep :80"
```

### Backend Pool Association
```bash
# Verify NIC is in backend pool
az network nic show \
  --resource-group <rg-name> \
  --name <nic-name> \
  --query "ipConfigurations[0].loadBalancerBackendAddressPools"
```

### NSG Rules
```bash
# Check effective NSG rules
az network nic list-effective-nsg \
  --resource-group <rg-name> \
  --name <nic-name>
```

## Migration Steps

To apply this architecture to existing deployment:

1. **Terraform Plan**: Review changes
   ```bash
   terraform plan
   ```

2. **Apply Changes**: Deploy Load Balancer
   ```bash
   terraform apply
   ```

3. **Verify Health**: Check Load Balancer backend health
   ```bash
   az network lb show \
     --resource-group <rg-name> \
     --name <lb-name> \
     --query "backendAddressPools[0].backendIPConfigurations"
   ```

4. **Test Access**: Use new Load Balancer IP
   ```bash
   curl http://<new-lb-ip>
   ```

5. **Update DNS**: Point domain to Load Balancer IP (if applicable)

## Best Practices

1. **Health Probes**: Always configure health probes matching your application
2. **Backend Pool**: Use multiple VMs for high availability
3. **NSG Rules**: Restrict inbound to Load Balancer subnet only
4. **Monitoring**: Enable Azure Monitor for Load Balancer metrics
5. **Scaling**: Use VM Scale Sets for auto-scaling (future enhancement)

## References

- [Azure Load Balancer Documentation](https://docs.microsoft.com/azure/load-balancer/)
- [NAT Gateway Documentation](https://docs.microsoft.com/azure/virtual-network/nat-gateway/)
- [Standard Load Balancer and NAT Gateway](https://docs.microsoft.com/azure/load-balancer/load-balancer-outbound-connections)
