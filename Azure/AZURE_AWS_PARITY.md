# Azure Infrastructure - AWS Parity Update

## Overview
Azure infrastructure has been updated to achieve feature parity with the proven AWS architecture, ensuring consistent deployment and automated nginx configuration across both cloud providers.

## Key Changes Made

### 1. **Native Nginx Architecture** ✅
- **Before**: Docker Nginx container (`nginx:alpine`)
- **After**: Native Nginx systemd service (matches AWS)
- **Benefit**: Simpler architecture, better performance, consistent with AWS

### 2. **Consolidated Configuration Approach** ✅
- **Before**: Separate config files per container
- **After**: Single `upstreams.conf` + single `locations.conf`
- **Benefit**: Eliminates server block conflicts, ensures consistent routing

### 3. **IP-Based Proxy Routing** ✅
- **Before**: Docker DNS resolution using container names
- **After**: jq-based IP extraction from Docker network
- **Implementation**: 
  ```bash
  docker inspect $container_id | jq -r '.[0].NetworkSettings.Networks["app-network"].IPAddress'
  ```
- **Benefit**: More reliable than Go templates, consistent with AWS

### 4. **Path Rewriting Logic** ✅
- **Added**: `rewrite ^/dev/<service>/(.*) /$1 break;`
- **Purpose**: Strips path prefix before proxying to backends
- **Example**: `/dev/beneficiaries/api/v1/beneficiaries` → `/api/v1/beneficiaries`
- **Benefit**: Applications receive expected paths without modification

### 5. **Automated Config Regeneration** ✅
- **Before**: Individual container configs
- **After**: Consolidated rebuild on any container change
- **Implementation**: `rebuild_all_configs()` function
- **Benefit**: Handles multi-container scenarios, ensures consistency

### 6. **GitHub Runner Docker Access** ✅
- **Added**: `usermod -aG docker azureuser`
- **Added**: Service restart after docker group addition
- **Benefit**: Runner can deploy containers without permission issues

## File Structure Comparison

### AWS (Reference)
```
/etc/nginx/
├── nginx.conf (main config with include)
└── conf.d/
    └── auto-generated/
        ├── upstreams.conf (all backends)
        └── locations.conf (all routes)

/usr/local/bin/
└── nginx-auto-config.sh (monitoring script)

/etc/systemd/system/
└── nginx-auto-config.service
```

### Azure (Updated to Match)
```
/etc/nginx/
├── nginx.conf (main config with include)
└── conf.d/
    └── auto-generated/
        ├── upstreams.conf (all backends)
        └── locations.conf (all routes)

/usr/local/bin/
└── nginx-auto-config.sh (monitoring script)

/etc/systemd/system/
└── nginx-auto-config.service
```

## Configuration Flow

### 1. Container Starts
```
Docker Event → nginx-auto-config detects start
↓
collect_container_info() extracts:
  - Container name
  - IP address (via jq)
  - Port (from label or auto-detect)
  - Path (from nginx.path label)
↓
Store in /tmp/nginx-containers.tmp
```

### 2. Config Generation
```
generate_consolidated_config() reads temp file
↓
Generate upstreams.conf:
  upstream beneficiaries_backend {
    server 172.18.0.5:8080;
    keepalive 32;
  }
↓
Generate locations.conf:
  location /dev/beneficiaries/ {
    rewrite ^/dev/beneficiaries/(.*) /$1 break;
    proxy_pass http://beneficiaries_backend;
    proxy_set_header Host $host;
    ...
  }
↓
nginx -t && systemctl reload nginx
```

### 3. Request Routing
```
Client Request: http://vm-ip/dev/beneficiaries/api/v1/beneficiaries
↓
Nginx matches: location /dev/beneficiaries/
↓
Path rewrite: /api/v1/beneficiaries
↓
Proxy to: http://172.18.0.5:8080/api/v1/beneficiaries
↓
Application processes: /api/v1/beneficiaries ✅
```

## Container Label Requirements

Both AWS and Azure now use identical label specifications:

```yaml
services:
  beneficiaries:
    image: beneficiaries:latest
    networks:
      - app-network
    labels:
      nginx.enable: "true"              # Optional, default true
      nginx.path: "/dev/beneficiaries"  # Required
      nginx.port: "8080"                # Optional, auto-detected
```

## Testing Procedure

### 1. Deploy Azure Infrastructure
```bash
# Via GitHub Actions workflow: azure-infrastructure-oidc
# Or via Terraform:
cd infrastructure/Azure/terraform
terraform apply
```

### 2. Verify Nginx Service
```bash
# SSH to Azure VM
ssh azureuser@<azure-vm-ip>

# Check nginx status
sudo systemctl status nginx

# Check auto-config service
sudo systemctl status nginx-auto-config.service

# View logs
sudo tail -f /var/log/nginx-auto-config.log
```

### 3. Deploy Applications
```bash
# Via GitHub Actions workflow: sit-environment-generic
# Should automatically configure nginx routes
```

### 4. Test Endpoints
```bash
# From sit-test-repo
export ALB_URL="http://<azure-vm-ip>"
./test-all-endpoints.sh
```

## Expected Outcomes

### ✅ Successful Deployment
- Nginx running on port 80
- nginx-auto-config service active
- Initial log: "No containers to configure"

### ✅ After App Deployment
- Containers detected on app-network
- Configs generated:
  - `/etc/nginx/conf.d/auto-generated/upstreams.conf`
  - `/etc/nginx/conf.d/auto-generated/locations.conf`
- Nginx reloaded automatically
- Endpoints accessible:
  - `http://vm-ip/dev/beneficiaries/health`
  - `http://vm-ip/dev/paymentprocessor/health`
  - `http://vm-ip/dev/paymentconsumer/health`

## Differences from AWS (Intentional)

| Feature | AWS | Azure | Reason |
|---------|-----|-------|--------|
| Load Balancer | ALB | None (VM direct) | Azure uses VM public IP |
| User Account | `ubuntu` | `azureuser` | Default Azure user |
| Cloud Init | user-data.sh | cloud-init.yaml | Different format |
| OIDC Provider | AWS OIDC | Azure OIDC | Cloud-specific |

**All nginx and application logic identical** ✅

## Troubleshooting

### Check Auto-Config Logs
```bash
sudo tail -100 /var/log/nginx-auto-config.log
```

### Manually Trigger Config Rebuild
```bash
sudo systemctl restart nginx-auto-config.service
```

### Verify Docker Network
```bash
docker network inspect app-network
```

### Test Nginx Config
```bash
sudo nginx -t
```

### View Generated Configs
```bash
cat /etc/nginx/conf.d/auto-generated/upstreams.conf
cat /etc/nginx/conf.d/auto-generated/locations.conf
```

## Rollback Plan

If issues occur, revert to previous cloud-init.yaml:
```bash
cd infrastructure/Azure/terraform/modules/vm
git checkout HEAD~1 cloud-init.yaml
terraform apply
```

## Next Steps

1. ✅ Azure cloud-init.yaml updated
2. ⏳ Deploy Azure infrastructure via Terraform/GitHub Actions
3. ⏳ Deploy applications via sit-environment-generic workflow
4. ⏳ Test all endpoints using test-all-endpoints.sh
5. ⏳ Verify logs show successful auto-configuration
6. ⏳ Confirm Azure behaves identically to AWS

## Success Criteria

- [ ] Azure VM deploys successfully
- [ ] Nginx service starts on port 80
- [ ] nginx-auto-config service monitors Docker events
- [ ] Applications deploy via GitHub Actions runner
- [ ] Configs auto-generate when containers start
- [ ] All endpoints respond correctly
- [ ] test-all-endpoints.sh passes all tests
- [ ] Behavior identical to AWS deployment

---

**Status**: Azure infrastructure updated to match AWS proven architecture ✅  
**Date**: 2024-11-24  
**AWS Reference**: `infrastructure/AWS/scripts/user-data.sh` (lines 290-550)  
**Azure Updated**: `infrastructure/Azure/terraform/modules/vm/cloud-init.yaml`
