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
    
    # Create the complete script content using a here document
    cat << EOF
#!/bin/sh
set -e

# Initialize TS_NAME with a unique name for this Tailscale instance
TS_NAME="$service"

# Automatically remove existing containers for this service only
echo "Removing existing $service containers..."
podman rm -f $service 2>/dev/null || true
podman rm -f npm-$service 2>/dev/null || true
podman rm -f tailscale-$service 2>/dev/null || true

EOF

    # Add Tailscale startup if included
    if [[ "$include_ts" == "yes" ]]; then
        cat << EOF
# Start Tailscale first with unique hostname
echo "Starting Tailscale..."
if ! podman ps --format '{{.Names}}' | grep -q "^tailscale-$service\$"; then
  podman run -d \\
    --name tailscale-$service \\
    --cap-add NET_ADMIN --cap-add NET_RAW \\
    --device /dev/net/tun \\
    -v /dev/net/tun:/dev/net/tun \\
    -v \$(pwd)/tailscale:/var/lib/tailscale \\
    -e TS_AUTHKEY="$auth_key" \\
    -e TS_STATE_DIR=/var/lib/tailscale \\
    -e TS_HOSTNAME="\$TS_NAME" \\
    -e TS_TAGS="tag:\$TS_NAME" \\
    -e TS_EXTRA_ARGS="--hostname=\$TS_NAME --accept-routes" \\
    $ts_image
fi

echo "Waiting for Tailscale..."
sleep 10

EOF
    fi

    # Add NPM startup if included
    if [[ "$include_npm" == "yes" ]]; then
        cat << EOF
# Start NPM
echo "Starting Nginx Proxy Manager..."
if ! podman ps --format '{{.Names}}' | grep -q "^npm-$service\$"; then
  podman run -d \\
    --name npm-$service \\
    --network container:tailscale-$service \\
    -e DB_SQLITE_FILE="/data/database.sqlite" \\
    -v \$(pwd)/npm/data:/data \\
    -v \$(pwd)/npm/letsencrypt:/etc/letsencrypt \\
    $npm_image
fi

echo "Waiting for NPM..."
sleep 5

EOF
    fi

    # Start main service command
    cat << EOF
# Start main service
echo "Starting $service..."
if ! podman ps --format '{{.Names}}' | grep -q "^$service\$"; then
  podman run -d \\
    --name $service \\
EOF

    # Add network configuration
    if [[ "$include_ts" == "yes" ]]; then
        echo "    --network container:tailscale-$service \\"
    fi

    # Add environment variables
    local env_vars_json
    env_vars_json=$(jq -c '.environment' <<<"$service_info")
    
    while IFS= read -r env_pair; do
        echo "    -e $env_pair \\"
    done < <(jq -r 'to_entries[] | "\(.key)=\"\(.value)\""' <<<"$env_vars_json")

    # Add volume mounts
    local volumes_json
    volumes_json=$(jq -c '.volumes' <<<"$service_info")
    
    while IFS= read -r volume_pair; do
        echo "    -v $volume_pair \\"
    done < <(jq -r 'to_entries[] | "\(.value):\(.key)"' <<<"$volumes_json")

    # Complete the service container command
    cat << EOF
    --restart $restart_policy \\
    $service_image
fi

echo "Waiting for $service..."
sleep 10

EOF

    # Add binding check if primary port exists
    if [[ -n "$primary_port" ]]; then
        cat << EOF
# Check binding configuration if service has ports defined
if [ -n "$primary_port" ]; then
  echo "Checking $service binding configuration..."
  sleep 5
  
  if podman exec $service sh -c "[ -f /config/config.xml ]" 2>/dev/null; then
    BIND_ADDRESS=\$(podman exec $service grep -oP '(?<=<BindAddress>)[^<]+' /config/config.xml 2>/dev/null || echo "Not found")
    
    if [ "\$BIND_ADDRESS" = "127.0.0.1" ]; then
      echo "Fixing binding address..."
      podman exec $service sed -i 's/<BindAddress>127.0.0.1</<BindAddress>*</g' /config/config.xml
      echo "Restarting $service..."
      podman restart $service
      sleep 5
    elif [ "\$BIND_ADDRESS" = "*" ]; then
      echo "Binding configuration is correct"
    fi
  else
    echo "Config file not found yet - $service may still be initializing"
  fi
fi

EOF
    fi

    # Add network information section
    cat << EOF
# Get Tailscale information
echo "Getting network information..."

# Install network tools if needed
podman exec tailscale-$service sh -c "command -v wget >/dev/null 2>&1 || (apk add --no-cache wget curl >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y wget curl >/dev/null 2>&1))" 2>/dev/null

# Get network details
TS_IP=\$(podman exec tailscale-$service tailscale ip -4 2>/dev/null || echo "Not available")
TS_HOSTNAME=\$(podman exec tailscale-$service tailscale status --self 2>/dev/null | head -1 | awk '{print \$2}' || echo "")
if [ -z "\$TS_HOSTNAME" ]; then
  TS_HOSTNAME="\$TS_NAME"
fi
TS_FQDN="\${TS_HOSTNAME}.ts.net"

# Run connectivity checks
echo ""
echo "Verifying services..."

EOF

    # Add connectivity checks
    if [[ "$include_npm" == "yes" ]]; then
        cat << EOF
# Check NPM connectivity
NPM_READY=\$(podman exec tailscale-$service wget -q --spider --timeout=5 http://localhost:81 2>/dev/null && echo "yes" || echo "no")
EOF
    fi
    
    if [[ -n "$primary_port" ]]; then
        cat << EOF
# Check service connectivity  
SERVICE_READY=\$(podman exec tailscale-$service wget -q --spider --timeout=5 http://localhost:$primary_port 2>/dev/null && echo "yes" || echo "no")
EOF
    fi

    # Add results display
    cat << EOF
# Display results
echo ""
echo "========================================"
echo "  $service Deployment Complete"
echo "========================================"
echo ""
echo "Network Information:"
echo "  Tailscale IP: \$TS_IP"
echo "  Hostname: \$TS_HOSTNAME"
echo "  FQDN: \$TS_FQDN"
echo ""
echo "Service Status:"
EOF

    # Add NPM status
    if [[ "$include_npm" == "yes" ]]; then
        cat << EOF
if [ "\$NPM_READY" = "yes" ]; then
  echo "  Nginx Proxy Manager: ✓ Ready"
else
  echo "  Nginx Proxy Manager: × Not ready"
fi
EOF
    fi

    # Add service status
    if [[ -n "$primary_port" ]]; then
        cat << EOF
if [ "\$SERVICE_READY" = "yes" ]; then
  echo "  $service: ✓ Ready"
else
  echo "  $service: × Not ready"
fi
EOF
    fi

    # Add access URLs
    cat << EOF
echo ""
echo "Access URLs:"
EOF

    if [[ "$include_npm" == "yes" ]]; then
        cat << EOF
echo "  NPM Admin: http://\$TS_FQDN:81"
EOF
    fi

    if [[ -n "$primary_port" ]]; then
        cat << EOF
echo "  $service: http://\$TS_FQDN:$primary_port"
EOF
    fi

    # Add multiple ports if they exist
    local port_count
    port_count=$(jq '.ports | length' <<<"$service_info")
    
    if [[ $port_count -gt 1 ]]; then
        cat << EOF
echo ""
echo "Additional Ports:"
EOF
        
        # Get all ports except the first one
        while IFS= read -r port; do
            cat << EOF
echo "  - Port $port: http://\$TS_FQDN:$port"
EOF
        done < <(jq -r '.ports | keys[1:][]' <<<"$service_info")
    fi

    # Add direct IP access
    cat << EOF
echo ""
echo "Direct IP Access:"
echo "  http://\$TS_IP:81 (NPM)"
EOF

    if [[ -n "$primary_port" ]]; then
        cat << EOF
echo "  http://\$TS_IP:$primary_port ($service)"
EOF
    fi

    # Add final troubleshooting note
    cat << EOF
echo ""

if [ "\$SERVICE_READY" != "yes" ]; then
  echo "Note: $service is not yet accessible."
  echo "Run './diagnose.sh' if the issue persists."
fi
EOF
}
