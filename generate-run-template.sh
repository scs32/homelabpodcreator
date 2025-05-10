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
    local script_content=""
    script_content+='#!/bin/sh
set -e

# Initialize TS_NAME with a unique name for this Tailscale instance
TS_NAME="'"$service"'"

# Automatically remove existing containers for this service only
echo "Removing existing '"$service"' containers..."
podman rm -f '"$service"' 2>/dev/null || true
podman rm -f npm-'"$service"' 2>/dev/null || true
podman rm -f tailscale-'"$service"' 2>/dev/null || true

'

    # Add Tailscale startup if included
    if [[ "$include_ts" == "yes" ]]; then
        script_content+='# Start Tailscale first with unique hostname
echo "Starting Tailscale..."
podman ps --format '"'"'{{.Names}}'"'"' | grep -q "^tailscale-'"$service"'$" || podman run -d \
  --name tailscale-'"$service"' \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun \
  -v /dev/net/tun:/dev/net/tun \
  -v $(pwd)/tailscale:/var/lib/tailscale \
  -e TS_AUTHKEY="'"$auth_key"'" \
  -e TS_STATE_DIR=/var/lib/tailscale \
  -e TS_HOSTNAME="$TS_NAME" \
  -e TS_TAGS="tag:$TS_NAME" \
  -e TS_EXTRA_ARGS="--hostname=$TS_NAME --accept-routes" \
  '"$ts_image"'

echo "Waiting for Tailscale..."
sleep 10

'
    fi

    # Add NPM startup if included
    if [[ "$include_npm" == "yes" ]]; then
        script_content+='# Start NPM
echo "Starting Nginx Proxy Manager..."
podman ps --format '"'"'{{.Names}}'"'"' | grep -q "^npm-'"$service"'$" || podman run -d \
  --name npm-'"$service"' \
  --network container:tailscale-'"$service"' \
  -e DB_SQLITE_FILE="/data/database.sqlite" \
  -v $(pwd)/npm/data:/data \
  -v $(pwd)/npm/letsencrypt:/etc/letsencrypt \
  '"$npm_image"'

echo "Waiting for NPM..."
sleep 5

'
    fi

    # Start main service command
    script_content+='# Start main service
echo "Starting '"$service"'..."
podman ps --format '"'"'{{.Names}}'"'"' | grep -q "^'"$service"'$" || podman run -d \
  --name '"$service"' \
'

    # Add network configuration
    if [[ "$include_ts" == "yes" ]]; then
        script_content+="  --network container:tailscale-$service \\"$'\n'
    fi

    # Add environment variables
    script_content+=$(add_environment_variables "$service_info")

    # Add volume mounts
    script_content+=$(add_volume_mounts "$service_info")

    # Complete the service container command
    script_content+='  --restart '"$restart_policy"' \
  '"$service_image"'

echo "Waiting for '"$service"'..."
sleep 10

'

    # Add binding check if primary port exists
    if [[ -n "$primary_port" ]]; then
        script_content+='# Check binding configuration if service has ports defined
if [ -n "'"$primary_port"'" ]; then
  echo "Checking '"$service"' binding configuration..."
  sleep 5
  
  if podman exec '"$service"' sh -c "[ -f /config/config.xml ]" 2>/dev/null; then
    BIND_ADDRESS=$(podman exec '"$service"' grep -oP '"'"'(?<=<BindAddress>)[^<]+'"'"' /config/config.xml 2>/dev/null || echo "Not found")
    
    if [ "$BIND_ADDRESS" = "127.0.0.1" ]; then
      echo "Fixing binding address..."
      podman exec '"$service"' sed -i '"'"'s/<BindAddress>127.0.0.1</<BindAddress>*/g'"'"' /config/config.xml
      echo "Restarting '"$service"'..."
      podman restart '"$service"'
      sleep 5
    elif [ "$BIND_ADDRESS" = "*" ]; then
      echo "Binding configuration is correct"
    fi
  else
    echo "Config file not found yet - '"$service"' may still be initializing"
  fi
fi

'
    fi

    # Add network information section
    script_content+='# Get Tailscale information
echo "Getting network information..."

# Install network tools if needed
podman exec tailscale-'"$service"' sh -c "command -v wget >/dev/null 2>&1 || (apk add --no-cache wget curl >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y wget curl >/dev/null 2>&1))" 2>/dev/null

# Get network details
TS_IP=$(podman exec tailscale-'"$service"' tailscale ip -4 2>/dev/null || echo "Not available")
TS_HOSTNAME=$(podman exec tailscale-'"$service"' tailscale status --self 2>/dev/null | head -1 | awk '"'"'{print $2}'"'"' || echo "")
if [ -z "$TS_HOSTNAME" ]; then
  TS_HOSTNAME="$TS_NAME"
fi
TS_FQDN="${TS_HOSTNAME}.ts.net"

# Run connectivity checks
echo ""
echo "Verifying services..."

'

    # Add connectivity checks
    script_content+=$(add_connectivity_checks "$include_npm" "$primary_port" "$service")

    # Add results display
    script_content+=$(add_results_display "$include_npm" "$primary_port" "$service_info" "$service")

    # Add final troubleshooting note
    script_content+='

if [ "$SERVICE_READY" != "yes" ]; then
  echo "Note: '"$service"' is not yet accessible."
  echo "Run '"'"'./diagnose.sh'"'"' if the issue persists."
fi
'

    # Output the complete script
    echo "$script_content"
}

# Helper function to add environment variables
add_environment_variables() {
    local service_info="$1"
    local env_vars_json
    local output=""
    
    env_vars_json=$(jq -c '.environment' <<<"$service_info")
    
    # Get all environment variables
    while IFS= read -r env_pair; do
        output+="  -e $env_pair \\"$'\n'
    done < <(jq -r 'to_entries[] | "\(.key)=\"\(.value)\""' <<<"$env_vars_json")
    
    echo "$output"
}

# Helper function to add volume mounts
add_volume_mounts() {
    local service_info="$1"
    local volumes_json
    local output=""
    
    volumes_json=$(jq -c '.volumes' <<<"$service_info")
    
    # Get all volume mounts
    while IFS= read -r volume_pair; do
        output+="  -v $volume_pair \\"$'\n'
    done < <(jq -r 'to_entries[] | "\(.value):\(.key)"' <<<"$volumes_json")
    
    echo "$output"
}

# Helper function to add connectivity checks
add_connectivity_checks() {
    local include_npm="$1"
    local primary_port="$2"
    local service="$3"
    local output=""
    
    if [[ "$include_npm" == "yes" ]]; then
        output+='# Check NPM connectivity
NPM_READY=$(podman exec tailscale-'"$service"' wget -q --spider --timeout=5 http://localhost:81 2>/dev/null && echo "yes" || echo "no")
'
    fi
    
    if [[ -n "$primary_port" ]]; then
        output+='# Check service connectivity  
SERVICE_READY=$(podman exec tailscale-'"$service"' wget -q --spider --timeout=5 http://localhost:'"$primary_port"' 2>/dev/null && echo "yes" || echo "no")
'
    fi
    
    echo "$output"
}

# Helper function to add results display
add_results_display() {
    local include_npm="$1"
    local primary_port="$2"
    local service_info="$3"
    local service="$4"
    local output=""
    
    # Start display section
    output+='# Display results
echo ""
echo "========================================"
echo "  '"$service"' Deployment Complete"
echo "========================================"
echo ""
echo "Network Information:"
echo "  Tailscale IP: $TS_IP"
echo "  Hostname: $TS_HOSTNAME"
echo "  FQDN: $TS_FQDN"
echo ""
echo "Service Status:"
'

    # Add NPM status
    if [[ "$include_npm" == "yes" ]]; then
        output+='if [ "$NPM_READY" = "yes" ]; then
  echo "  Nginx Proxy Manager: ✓ Ready"
else
  echo "  Nginx Proxy Manager: × Not ready"
fi
'
    fi

    # Add service status
    if [[ -n "$primary_port" ]]; then
        output+='if [ "$SERVICE_READY" = "yes" ]; then
  echo "  '"$service"': ✓ Ready"
else
  echo "  '"$service"': × Not ready"
fi
'
    fi

    # Add access URLs
    output+='echo ""
echo "Access URLs:"
'

    if [[ "$include_npm" == "yes" ]]; then
        output+='echo "  NPM Admin: http://$TS_FQDN:81"
'
    fi

    if [[ -n "$primary_port" ]]; then
        output+='echo "  '"$service"': http://$TS_FQDN:'"$primary_port"'"
'
    fi

    # Add multiple ports if they exist
    output+=$(add_additional_ports "$service_info" "$service")

    # Add direct IP access
    output+='echo ""
echo "Direct IP Access:"
echo "  http://$TS_IP:81 (NPM)"
'

    if [[ -n "$primary_port" ]]; then
        output+='echo "  http://$TS_IP:'"$primary_port"' ('"$service"')"
'
    fi

    output+='echo ""'
    
    echo "$output"
}

# Helper function to add additional ports
add_additional_ports() {
    local service_info="$1"
    local service="$2"
    local output=""
    
    # Check if there are additional ports
    local port_count
    port_count=$(jq '.ports | length' <<<"$service_info")
    
    if [[ $port_count -gt 1 ]]; then
        output+='echo ""
echo "Additional Ports:"
'
        
        # Get all ports except the first one
        while IFS= read -r port; do
            output+='echo "  - Port '"$port"': http://$TS_FQDN:'"$port"'"
'
        done < <(jq -r '.ports | keys[1:][]' <<<"$service_info")
    fi
    
    echo "$output"
}
