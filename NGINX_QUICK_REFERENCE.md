# Nginx Auto-Configuration Quick Reference

## TL;DR

Deploy containers with labels → Nginx automatically configured → No manual steps needed!

```bash
docker run -d \
  --name my-app \
  --network app-network \
  --label nginx.path=/my-app \
  my-app:latest
```

Access immediately at: `http://HOST_IP/my-app`

---

## Labels Cheat Sheet

| Label | Example | Result |
|-------|---------|--------|
| `nginx.path=/api` | Payment service | `http://HOST/api` → container |
| `nginx.host=app.example.com` | Web frontend | `http://app.example.com` → container |
| `nginx.port=8080` | Backend service | Proxy to port 8080 |
| `nginx.enable=false` | Special service | No auto-config |

---

## Common Patterns

### Pattern 1: Microservices (Path-Based)

```bash
# Payments
docker run -d --name payments --network app-network \
  --label nginx.path=/payments payment-svc:latest

# Users
docker run -d --name users --network app-network \
  --label nginx.path=/users user-svc:latest

# Orders
docker run -d --name orders --network app-network \
  --label nginx.path=/orders order-svc:latest
```

**Result:**
- `http://HOST/payments` → payments service
- `http://HOST/users` → users service
- `http://HOST/orders` → orders service

### Pattern 2: Multi-Domain (Host-Based)

```bash
# API
docker run -d --name api --network app-network \
  --label nginx.host=api.example.com api:latest

# Web App
docker run -d --name web --network app-network \
  --label nginx.host=app.example.com web:latest

# Admin
docker run -d --name admin --network app-network \
  --label nginx.host=admin.example.com admin:latest
```

**Result:**
- `http://api.example.com` → api service
- `http://app.example.com` → web service
- `http://admin.example.com` → admin service

### Pattern 3: Docker Compose

```yaml
version: '3.8'
services:
  backend:
    image: backend:latest
    networks: [app-network]
    labels:
      nginx.path: "/api"
      nginx.port: "8080"
  
  frontend:
    image: frontend:latest
    networks: [app-network]
    labels:
      nginx.host: "app.example.com"

networks:
  app-network:
    external: true
```

---

## Monitoring One-Liners

```bash
# Watch logs in real-time
tail -f /var/log/nginx-auto-config.log

# Check service status
systemctl status nginx-auto-config.service

# List generated configs
ls -l /opt/nginx/conf.d/auto-generated/

# View a config
cat /opt/nginx/conf.d/auto-generated/my-app.conf

# Test Nginx config
docker exec nginx nginx -t

# Restart service if needed
systemctl restart nginx-auto-config.service
```

---

## Troubleshooting

### Container not configured?

```bash
# 1. Check network
docker inspect my-app | grep -A 5 Networks
# Must be on "app-network"

# 2. Check labels
docker inspect my-app | grep -A 10 Labels
# Should show nginx.* labels

# 3. Check logs
tail -50 /var/log/nginx-auto-config.log
```

### Config error?

```bash
# Test Nginx
docker exec nginx nginx -t

# View errors
docker logs nginx
```

---

## Manual Override

Need custom config?

```bash
# 1. Disable auto-config
docker run -d --name special --network app-network \
  --label nginx.enable=false special:latest

# 2. Create manual config
cat > /opt/nginx/conf.d/special.conf <<'EOF'
server {
    listen 80;
    # Your custom config here
}
EOF

# 3. Reload
docker exec nginx nginx -s reload
```

---

## Files & Locations

| Item | Location |
|------|----------|
| Service | `nginx-auto-config.service` |
| Script | `/opt/nginx/auto-config.sh` |
| Logs | `/var/log/nginx-auto-config.log` |
| Auto Configs | `/opt/nginx/conf.d/auto-generated/` |
| Manual Configs | `/opt/nginx/conf.d/` |

---

## Full Documentation

- **AWS**: `infrastructure/AWS/NGINX_AUTO_CONFIG.md`
- **Azure**: `infrastructure/Azure/NGINX_AUTO_CONFIG.md`
- **Implementation**: `infrastructure/NGINX_AUTOMATION_SUMMARY.md`

---

## Features

✅ Zero configuration  
✅ Real-time monitoring  
✅ Auto reload  
✅ Auto cleanup  
✅ WebSocket support  
✅ Network filtering  
✅ Error handling  
✅ Comprehensive logging  

---

**That's it! Deploy with labels and everything else is automatic. 🚀**
