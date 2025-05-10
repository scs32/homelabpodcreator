#!/usr/bin/env bash

# Generate the run.sh script content
generate_run_template() {
    local service="$1"
    local auth_key="$2"
    local ts_image="$3"
    local npm_image="$4"
    local service_image="$5"
    local restart_policy="$6"
    local include_ts="$7"
    local include_npm="$8"
    local primary_port="$9"
    local service_info="${10}"
    
    # Start building the script
    cat << 'EOF_HEADER'
#!/bin/sh
set -e

# Initialize TS_NAME with a unique name for this Tailscale instance
TS_NAME="SERVICE_NAME"

# Automatically remove existing containers for this service only
echo "Removing existing SERVICE_NAME containers..."
podman rm -f SERVICE_NAME 2>/dev/null || true
podman rm -f npm-SERVICE_NAME 2>/dev/null || true
podman rm -f tailscale-SERVICE_NAME 2>/dev/null || true

EOF_HEADER

    # Add Tailscale startup if included
    if [[ "$include_ts" == "yes" ]]; then
        cat << 'EOF_TAILSCALE'
# Start Tailscale first with unique hostname
echo "Starting Tailscale..."
podman ps --format '{{.Names}}' | grep -q "^tailscale-SERVICE_NAME$" || podman run -d \
  --name tailscale-SERVICE_NAME \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun \
  -v /dev/net/tun:/dev/net/tun \
  -v $(pwd)/tailscale:/var/lib/tailscale \
  -e TS_AUTHKEY="AUTH_KEY" \
  -e TS_STATE_DIR=/var/lib/tailscale \
  -e TS_HOSTNAME="$TS_NAME" \
  -e TS_TAGS="tag:$TS_NAME" \
  -e TS_EXTRA_ARGS="--hostname=$TS_NAME --accept-routes" \
  TAILSCALE_IMAGE

echo "Waiting for Tailscale..."
sleep 10

EOF_TAILSCALE
    fi

    # Add NPM startup if included
    if [[ "$include_npm" == "yes" ]]; then
        cat << 'EOF_NPM'
# Start NPM
echo "Starting Nginx Proxy Manager..."
podman ps --format '{{.Names}}' | grep -q "^npm-SERVICE_NAME$" || podman run -d \
  --name npm-SERVICE_NAME \
  --network container:tailscale-SERVICE_NAME \
  -e DB_SQLITE_FILE="/data/database.sqlite" \
  -v $(pwd)/npm/data:/data \
  -v $(pwd)/npm/letsencrypt:/etc/letsencrypt \
  NPM_IMAGE

echo "Waiting for NPM..."
sleep 5

EOF_NPM
    fi

    # Start main service command
    cat << 'EOF_SERVICE_START'
# Start main service
echo "Starting SERVICE_NAME..."
podman ps --format '{{.Names}}' | grep -q "^SERVICE_NAME$" || podman run -d \
  --name SERVICE_NAME \
EOF_SERVICE_START

    # Add network configuration
    if [[ "$include_ts" == "yes" ]]; then
        echo "  --network container:tailscale-SERVICE_NAME \\"
    fi

    # Add environment variables
    add_environment_variables "$service_info"

    # Add volume mounts
    add_volume_mounts "$service_info"

    # Complete the service container command
    cat << 'EOF_SERVICE_COMPLETE'
  --restart RESTART_POLICY \
  SERVICE_IMAGE

echo "Waiting for SERVICE_NAME..."
sleep 10

EOF_SERVICE_COMPLETE

    # Add binding check if primary port exists
    if [[ -n "$primary_port" ]]; then
        cat << 'EOF_BINDING_CHECK'
# Check binding configuration if service has ports defined
if [ -n "PRIMARY_PORT" ]; then
  echo "Checking SERVICE_NAME binding configuration..."
  sleep 5
  
  if podman exec SERVICE_NAME sh -c "[ -f /config/config.xml ]" 2>/dev/null; then
    BIND_ADDRESS=$(podman exec SERVICE_NAME grep -oP '(?<=<BindAddress>)[^<]+' /config/config.xml 2>/dev/null || echo "Not found")
    
    if [ "$BIND_ADDRESS" = "127.0.0.1" ]; then
      echo "Fixing binding address..."
      podman exec SERVICE_NAME sed -i 's/<BindAddress>127.0.0.1</<BindAddress>*</g' /config/config.xml
      echo "Restarting SERVICE_NAME..."
      podman restart SERVICE_NAME
      sleep 5
    elif [ "$BIND_ADDRESS" = "*" ]; then
      echo "Binding configuration is correct"
    fi
  else
    echo "Config file not found yet - SERVICE_NAME may still be initializing"
  fi
fi

EOF_BINDING_CHECK
    fi

    # Add network information section
    cat << 'EOF_NETWORK_INFO'
# Get Tailscale information
echo "Getting network information..."

# Install network tools if needed
podman exec tailscale-SERVICE_NAME sh -c "command -v wget >/dev/null 2>&1 || (apk add --no-cache wget curl >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y wget curl >/dev/null 2>&1))" 2>/dev/null

# Get network details
TS_IP=$(podman exec tailscale-SERVICE_NAME tailscale ip -4 2>/dev/null || echo "Not available")
TS_HOSTNAME=$(podman exec tailscale-SERVICE_NAME tailscale status --self 2>/dev/null | head -1 | awk '{print $2}' || echo "")
if [ -z "$TS_HOSTNAME" ]; then
  TS_HOSTNAME="$TS_NAME"
fi
TS_FQDN="${TS_HOSTNAME}.ts.net"

# Run connectivity checks
echo ""
echo "Verifying services..."

EOF_NETWORK_INFO

    # Add connectivity checks
    add_connectivity_checks "$include_npm" "$primary_port"

    # Add results display
    add_results_display "$include_npm" "$primary_port" "$service_info"

    # Add final troubleshooting note
    cat << 'EOF_FOOTER'

if [ "$SERVICE_READY" != "yes" ]; then
  echo "Note: SERVICE_NAME is not yet accessible."
  echo "Run './diagnose.sh' if the issue persists."
fi
EOF_FOOTER

    # Replace all placeholders
    sed -e "s|SERVICE_NAME|$service|g" \
        -e "s|AUTH_KEY|$auth_key|g" \
        -e "s|TAILSCALE_IMAGE|$ts_image|g" \
        -e "s|NPM_IMAGE|$npm_image|g" \
        -e "s|RESTART_POLICY|$restart_policy|g" \
        -e "s|SERVICE_IMAGE|$service_image|g" \
        -e "s|PRIMARY_PORT|$primary_port|g"
}

# Helper function to add environment variables
add_environment_variables() {
    local service_info="$1"
    local env_vars_json
    
    env_vars_json=$(jq -c '.environment' <<<"$service_info")
    
    # Get all environment variables
    while IFS= read -r env_pair; do
        echo "  -e $env_pair \\"
    done < <(jq -r 'to_entries[] | "\(.key)=\"\(.value)\""' <<<"$env_vars_json")
}

# Helper function to add volume mounts
add_volume_mounts() {
    local service_info="$1"
    local volumes_json
    
    volumes_json=$(jq -c '.volumes' <<<"$service_info")
    
    # Get all volume mounts
    while IFS= read -r volume_pair; do
        echo "  -v $volume_pair \\"
    done < <(jq -r 'to_entries[] | "\(.value):\(.key)"' <<<"$volumes_json")
}

# Helper function to add connectivity checks
add_connectivity_checks() {
    local include_npm="$1"
    local primary_port="$2"
    
    if [[ "$include_npm" == "yes" ]]; then
        cat << 'EOF_NPM_CHECK'
# Check NPM connectivity
NPM_READY=$(podman exec tailscale-SERVICE_NAME wget -q --spider --timeout=5 http://localhost:81 2>/dev/null && echo "yes" || echo "no")
EOF_NPM_CHECK
    fi
    
    if [[ -n "$primary_port" ]]; then
        cat << 'EOF_SERVICE_CHECK'
# Check service connectivity  
SERVICE_READY=$(podman exec tailscale-SERVICE_NAME wget -q --spider --timeout=5 http://localhost:PRIMARY_PORT 2>/dev/null && echo "yes" || echo "no")
EOF_SERVICE_CHECK
    fi
}

# Helper function to add results display
add_results_display() {
    local include_npm="$1"
    local primary_port="$2"
    local service_info="$3"
    
    # Start display section
    cat << 'EOF_DISPLAY_START'
# Display results
echo ""
echo "========================================"
echo "  SERVICE_NAME Deployment Complete"
echo "========================================"
echo ""
echo "Network Information:"
echo "  Tailscale IP: $TS_IP"
echo "  Hostname: $TS_HOSTNAME"
echo "  FQDN: $TS_FQDN"
echo ""
echo "Service Status:"
EOF_DISPLAY_START

    # Add NPM status
    if [[ "$include_npm" == "yes" ]]; then
        cat << 'EOF_NPM_STATUS'
if [ "$NPM_READY" = "yes" ]; then
  echo "  Nginx Proxy Manager: ✓ Ready"
else
  echo "  Nginx Proxy Manager: × Not ready"
fi
EOF_NPM_STATUS
    fi

    # Add service status
    if [[ -n "$primary_port" ]]; then
        cat << 'EOF_SERVICE_STATUS'
if [ "$SERVICE_READY" = "yes" ]; then
  echo "  SERVICE_NAME: ✓ Ready"
else
  echo "  SERVICE_NAME: × Not ready"
fi
EOF_SERVICE_STATUS
    fi

    # Add access URLs
    cat << 'EOF_URLS_START'
echo ""
echo "Access URLs:"
EOF_URLS_START

    if [[ "$include_npm" == "yes" ]]; then
        cat << 'EOF_NPM_URL'
echo "  NPM Admin: http://$TS_FQDN:81"
EOF_NPM_URL
    fi

    if [[ -n "$primary_port" ]]; then
        cat << 'EOF_SERVICE_URL'
echo "  SERVICE_NAME: http://$TS_FQDN:PRIMARY_PORT"
EOF_SERVICE_URL
    fi

    # Add multiple ports if they exist
    add_additional_ports "$service_info"

    # Add direct IP access
    cat << 'EOF_DIRECT_ACCESS'
echo ""
echo "Direct IP Access:"
echo "  http://$TS_IP:81 (NPM)"
EOF_DIRECT_ACCESS

    if [[ -n "$primary_port" ]]; then
        cat << 'EOF_PRIMARY_IP'
echo "  http://$TS_IP:PRIMARY_PORT (SERVICE_NAME)"
EOF_PRIMARY_IP
    fi

    echo 'echo ""'
}

# Helper function to add additional ports
add_additional_ports() {
    local service_info="$1"
    
    # Check if there are additional ports
    local port_count
    port_count=$(jq '.ports | length' <<<"$service_info")
    
    if [[ $port_count -gt 1 ]]; then
        cat << 'EOF_ADDITIONAL_START'
echo ""
echo "Additional Ports:"
EOF_ADDITIONAL_START
        
        # Get all ports except the first one
        while IFS= read -r port; do
            cat << EOF_PORT
echo "  - Port $port: http://\\\$TS_FQDN:$port"
EOF_PORT
        done < <(jq -r '.ports | keys[1:][]' <<<"$service_info")
    fi
}
