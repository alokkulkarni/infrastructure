#!/bin/bash
# Diagnostic script for Nginx auto-configuration issues
# Run this on the EC2 instance via SSM or SSH

echo "======================================"
echo "Nginx Auto-Configuration Diagnostics"
echo "======================================"
echo ""

echo "1. Checking Docker containers on app-network:"
echo "--------------------------------------"
docker ps --filter "network=app-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "2. Checking nginx-auto-config service status:"
echo "--------------------------------------"
systemctl status nginx-auto-config.service --no-pager
echo ""

echo "3. Checking auto-generated Nginx configs:"
echo "--------------------------------------"
ls -lah /etc/nginx/conf.d/auto-generated/ 2>/dev/null || echo "Directory doesn't exist!"
echo ""

echo "4. Content of auto-generated configs (if any):"
echo "--------------------------------------"
for config in /etc/nginx/conf.d/auto-generated/*.conf 2>/dev/null; do
    if [ -f "$config" ]; then
        echo "=== $config ==="
        cat "$config"
        echo ""
    fi
done
echo ""

echo "5. Checking nginx-auto-config logs (last 50 lines):"
echo "--------------------------------------"
tail -50 /var/log/nginx-auto-config.log 2>/dev/null || echo "Log file doesn't exist!"
echo ""

echo "6. Checking Nginx configuration test:"
echo "--------------------------------------"
nginx -t
echo ""

echo "7. Checking Nginx main config includes:"
echo "--------------------------------------"
grep -A5 "include.*conf.d" /etc/nginx/nginx.conf
echo ""

echo "8. Container labels for nginx config:"
echo "--------------------------------------"
docker ps --filter "network=app-network" --format "{{.Names}}" | while read container; do
    echo "Container: $container"
    docker inspect "$container" --format '{{range $key, $value := .Config.Labels}}  {{$key}}: {{$value}}{{"\n"}}{{end}}' | grep nginx
    echo ""
done
echo ""

echo "9. Container IPs on app-network:"
echo "--------------------------------------"
docker network inspect app-network --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'
echo ""

echo "10. Nginx error log (last 20 lines):"
echo "--------------------------------------"
tail -20 /var/log/nginx/error.log 2>/dev/null || echo "No error log found"
echo ""

echo "======================================"
echo "Diagnostics Complete"
echo "======================================"
