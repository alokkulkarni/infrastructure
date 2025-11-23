#!/bin/bash
# Nginx Auto-Configuration for Docker Containers
# Watches Docker events and generates Nginx configs using container IPs

LOG_FILE="/var/log/nginx-auto-config.log"
CONFIG_DIR="/etc/nginx/conf.d/auto-generated"

mkdir -p $CONFIG_DIR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

generate_config() {
    local container_id=$1
    local container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/^\///')
    
    # Get container IP from app-network using jq for reliability
    local container_ip=$(docker inspect $container_id | jq -r '.[0].NetworkSettings.Networks["app-network"].IPAddress // empty' 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "Container $container_name not on app-network, skipping"
        return
    fi
    
    # Get labels
    local nginx_enable=$(docker inspect --format='{{index .Config.Labels "nginx.enable"}}' $container_id)
    local nginx_path=$(docker inspect --format='{{index .Config.Labels "nginx.path"}}' $container_id)
    local nginx_port=$(docker inspect --format='{{index .Config.Labels "nginx.port"}}' $container_id)
    local nginx_host=$(docker inspect --format='{{index .Config.Labels "nginx.host"}}' $container_id)
    
    # Skip if disabled
    if [ "$nginx_enable" == "false" ]; then
        log "Container $container_name has nginx.enable=false, skipping"
        return
    fi
    
    # Require nginx.path label
    if [ -z "$nginx_path" ] || [ "$nginx_path" == "<no value>" ]; then
        log "No nginx.path label for $container_name, skipping"
        return
    fi
    
    # Get internal container port (not host port)
    if [ -z "$nginx_port" ] || [ "$nginx_port" == "<no value>" ]; then
        # Auto-detect internal port from exposed ports
        nginx_port=$(docker inspect --format='{{range $key, $value := .Config.ExposedPorts}}{{$key}}{{end}}' $container_id | cut -d'/' -f1 | head -n1)
    fi
    
    if [ -z "$nginx_port" ]; then
        log "Could not determine port for $container_name, skipping"
        return
    fi
    
    local config_file="$CONFIG_DIR/${container_name}.conf"
    
    log "Generating config for $container_name"
    log "  Container IP: $container_ip"
    log "  Container Port: $nginx_port"
    log "  Path: $nginx_path"
    
    # Generate Nginx config
    cat > $config_file <<NGINXCONF
# Auto-generated for $container_name
# Generated: $(date)
# Container IP: $container_ip

upstream ${container_name}_backend {
    server ${container_ip}:${nginx_port};
}

server {
    listen 80;
NGINXCONF

    # Add server_name if specified
    if [ -n "$nginx_host" ] && [ "$nginx_host" != "<no value>" ]; then
        echo "    server_name $nginx_host;" >> $config_file
    fi
    
    cat >> $config_file <<NGINXCONF
    
    location $nginx_path {
        proxy_pass http://${container_name}_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINXCONF
    
    # Test and reload
    log "Testing nginx configuration..."
    if nginx -t 2>&1 | tee -a $LOG_FILE; then
        log "Reloading nginx..."
        systemctl reload nginx
        log "✅ Configuration for $container_name applied successfully"
    else
        log "❌ Nginx configuration test failed, removing $config_file"
        rm -f $config_file
    fi
}

remove_config() {
    local container_name=$1
    local config_file="$CONFIG_DIR/${container_name}.conf"
    
    if [ -f "$config_file" ]; then
        log "Removing config for $container_name"
        rm -f $config_file
        nginx -t && systemctl reload nginx
        log "✅ Configuration for $container_name removed"
    fi
}

# Initialize with existing containers
log "Initializing: scanning existing containers on app-network..."
docker ps --filter "network=app-network" --format '{{.ID}}' | while read cid; do
    generate_config $cid
done

# Monitor Docker events
log "Monitoring Docker events..."
docker events --filter 'type=container' --filter 'event=start' --filter 'event=die' --format '{{json .}}' | while read event; do
    event_type=$(echo $event | jq -r '.status')
    container_id=$(echo $event | jq -r '.id')
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    
    log "Event: $event_type for $container_name"
    
    case $event_type in
        start)
            sleep 2
            generate_config $container_id
            ;;
        die)
            remove_config $container_name
            ;;
    esac
done
