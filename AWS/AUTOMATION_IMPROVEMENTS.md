# Automated Nginx Configuration - Improvements Applied

## Problem Summary

After manual deployment testing, we discovered that the nginx-auto-config service had critical issues:

1. **Multiple Server Blocks Conflict**: Generated separate `server {}` blocks for each container, all listening on port 80, which conflicted with the default server block
2. **Missing Path Rewriting**: Applications expect paths without the `/dev/<service>` prefix, but configs didn't strip this
3. **IP Extraction Bug**: Go template returned empty values (already fixed with jq)

## Manual Solution That Worked

Successfully tested on instance `i-01f5b800ef8c6eb80`:

```nginx
# In /etc/nginx/nginx.conf default server block:
location /dev/beneficiaries/ { 
    rewrite ^/dev/beneficiaries/(.*) /$1 break; 
    proxy_pass http://172.18.0.6:8080;
    proxy_set_header Host $host;
}
location /dev/paymentprocessor/ { 
    rewrite ^/dev/paymentprocessor/(.*) /$1 break; 
    proxy_pass http://172.18.0.5:8081;
    proxy_set_header Host $host;
}
location /dev/paymentconsumer/ { 
    rewrite ^/dev/paymentconsumer/(.*) /$1 break; 
    proxy_pass http://172.18.0.7:8082;
    proxy_set_header Host $host;
}
```

**Result**: All services returned healthy status ✅

## Automated Solution Implemented

### Architecture Changes

**Before** (per-container server blocks):
```bash
# Generated separate files: beneficiaries.conf, paymentprocessor.conf, etc.
server {
    listen 80;
    location /dev/beneficiaries { ... }
}
server {
    listen 80;
    location /dev/paymentprocessor { ... }
}
```
❌ Problem: Multiple server blocks on port 80 conflict

**After** (consolidated location blocks):
```bash
# Generated files:
# - upstreams.conf: all upstream definitions
# - locations.conf: all location blocks
# Included in the default server block in nginx.conf
```
✅ Solution: Single server block with multiple locations

### Code Changes

#### 1. New `collect_container_info()` Function
- Validates container is on app-network
- Extracts labels: `nginx.enable`, `nginx.path`, `nginx.port`
- Uses jq for reliable IP extraction
- Stores container info in temp file for batch processing

#### 2. New `generate_consolidated_config()` Function
- Generates `upstreams.conf` with all upstream backends
- Generates `locations.conf` with all location blocks
- **Includes path rewriting**: `rewrite ^$path/(.*) /$1 break;`
- **Uses trailing slashes**: `location /dev/beneficiaries/` (not `/dev/beneficiaries`)
- Tests config before reloading

#### 3. New `rebuild_all_configs()` Function
- Collects all containers on app-network
- Regenerates both upstreams and locations files
- Called on:
  - Service startup
  - Any container start/stop event

#### 4. Updated `nginx.conf` Template
- Includes `locations.conf` inside default server block
- Includes `upstreams.conf` at http level
- Creates placeholder files to prevent nginx errors before containers start

#### 5. Simplified Event Monitoring
- Monitors Docker events for container start/stop
- Always rebuilds ALL configs on any change (ensures consistency)
- No per-container add/remove logic (simpler and more reliable)

### File Structure

```
/etc/nginx/
├── nginx.conf                          # Main config with default server block
└── conf.d/
    └── auto-generated/
        ├── upstreams.conf              # All upstream backends (http level)
        └── locations.conf              # All location blocks (server level)
```

## Benefits

1. **✅ No Server Block Conflicts**: Only one server block on port 80
2. **✅ Automatic Path Rewriting**: Applications receive correct paths
3. **✅ Simplified Logic**: One rebuild function instead of add/remove per container
4. **✅ Atomic Updates**: All configs updated together for consistency
5. **✅ Fault Tolerant**: Placeholder files prevent nginx startup errors

## Testing Plan

### 1. Deploy Fresh Infrastructure
```bash
cd infrastructure/AWS/terraform/environments/dev
terraform destroy -auto-approve
terraform apply -auto-approve
```

### 2. Verify Auto-Configuration
After GitHub Actions deployment completes:

```bash
# Check auto-generated files exist
ls -la /etc/nginx/conf.d/auto-generated/

# View generated upstreams
cat /etc/nginx/conf.d/auto-generated/upstreams.conf

# View generated locations
cat /etc/nginx/conf.d/auto-generated/locations.conf

# Test nginx config
nginx -t

# Check service logs
journalctl -u nginx-auto-config.service -n 50
```

### 3. Test Endpoints
```bash
ALB_URL="<your-alb-url>"

# Should return {"status":"UP"}
curl $ALB_URL/dev/beneficiaries/actuator/health
curl $ALB_URL/dev/paymentprocessor/actuator/health
curl $ALB_URL/dev/paymentconsumer/actuator/health
```

### 4. Verify Dynamic Updates
```bash
# Stop a container
docker stop beneficiaries

# Check logs - should rebuild configs
journalctl -u nginx-auto-config.service -n 10

# Restart container
docker start beneficiaries

# Check logs again - should rebuild configs
journalctl -u nginx-auto-config.service -n 10

# Endpoint should work again
curl $ALB_URL/dev/beneficiaries/actuator/health
```

## Rollback Plan

If issues occur, the working manual configuration is documented above and can be applied via SSM:

```bash
# Access instance via SSM
aws ssm start-session --target i-<instance-id> --region eu-west-2

# Apply manual configuration
sudo bash
# ... apply manual nginx.conf changes ...
nginx -t && systemctl reload nginx
```

## Container Labels Required

For auto-configuration to work, containers must have:

```yaml
services:
  myapp:
    labels:
      nginx.enable: "true"          # Optional: defaults to true
      nginx.path: "/dev/myapp"      # Required: URL path
      nginx.port: "8080"            # Required: internal container port
    networks:
      - app-network                 # Required: must be on app-network
```

## Next Steps

1. ✅ Code changes applied to `user-data.sh`
2. ⏳ Deploy to fresh infrastructure
3. ⏳ Verify automated configuration works
4. ⏳ Test dynamic updates (container restarts)
5. ⏳ Document any additional findings

## Files Modified

- `/infrastructure/AWS/terraform/modules/ec2/user-data.sh` - Complete rewrite of nginx auto-config logic

## Expected Outcome

After `terraform apply`, the deployment should complete and all three service health endpoints should be accessible via the ALB without any manual SSM intervention.
