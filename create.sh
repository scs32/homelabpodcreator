#!/usr/bin/env bash
set -euo pipefail

# Read the JSON blob from stdin
CONFIG_JSON="$(cat)"
if [[ -z "$CONFIG_JSON" ]]; then
  echo "Error: no JSON input provided" >&2
  exit 1
fi

# Parse all inputs
service=$(jq -r '.container'        <<<"$CONFIG_JSON")
image_raw=$(jq -r '.image'          <<<"$CONFIG_JSON")
restart_policy=$(jq -r '.restart_policy' <<<"$CONFIG_JSON")
auth_key=$(jq -r '.auth_key'        <<<"$CONFIG_JSON")
base_path=$(jq -r '.base_path'      <<<"$CONFIG_JSON")
include_ts=$(jq -r '.include_tailscale' <<<"$CONFIG_JSON")
include_npm=$(jq -r '.include_npm'  <<<"$CONFIG_JSON")

# Safe image qualifier
qualify_image(){
  local img="${1:-}"
  local prefix="${img%%/*}"
  if [[ -n "$img" && "$prefix" != *.* && "$prefix" != *:* ]]; then
    echo "docker.io/$img"
  else
    echo "$img"
  fi
}

# Final images
service_image=$(qualify_image "$image_raw")
ts_image=$(qualify_image "tailscale/tailscale:stable")
npm_image=$(qualify_image "jc21/nginx-proxy-manager:latest")

# Extract env & volume keys
readarray -t env_keys < <(jq -r '.environment|keys[]'  <<<"$CONFIG_JSON")
readarray -t vol_keys < <(jq -r '.volumes   |keys[]'  <<<"$CONFIG_JSON")

# Extract port mappings if they exist
ports_json=$(jq -r '.ports // {}' <<<"$CONFIG_JSON")
declare -A ports_map
readarray -t port_keys < <(jq -r 'keys[]' <<<"$ports_json" 2>/dev/null || echo "")

# Build maps
declare -A env_vars volumes_map
for k in "${env_keys[@]}"; do
  env_vars[$k]=$(jq -r --arg k "$k" '.environment[$k]' <<<"$CONFIG_JSON")
done
for v in "${vol_keys[@]}"; do
  volumes_map[$v]=$(jq -r --arg v "$v" '.volumes[$v]' <<<"$CONFIG_JSON")
done

# Build ports map
for p in "${port_keys[@]}"; do
  if [[ -n "$p" ]]; then
    ports_map[$p]=$(jq -r --arg p "$p" '.ports[$p]' <<<"$ports_json")
  fi
done

# Get primary port (used for connectivity checks)
primary_port=""
if [[ ${#port_keys[@]} -gt 0 && -n "${port_keys[0]}" ]]; then
  primary_port="${port_keys[0]}"
fi

# Prepare directories
svc_dir="$base_path/$service"
mkdir -p "$svc_dir"
echo "Ensured service dir: $svc_dir"

if [[ "$include_npm" == "yes" ]]; then
  mkdir -p "$svc_dir/npm/data" "$svc_dir/npm/letsencrypt"
  echo "Ensured NPM storage under $svc_dir/npm"
fi

# Create tailscale directory for state persistence
if [[ "$include_ts" == "yes" ]]; then
  mkdir -p "$svc_dir/tailscale"
  echo "Ensured Tailscale state directory under $svc_dir/tailscale"
fi

for hp in "${volumes_map[@]}"; do
  mkdir -p "$hp"
  echo "Ensured host volume: $hp"
  # Set proper ownership if PUID/PGID are provided
  if [[ -n "${env_vars[PUID]:-}" && -n "${env_vars[PGID]:-}" ]]; then
    chown -R ${env_vars[PUID]}:${env_vars[PGID]} "$hp" 2>/dev/null || sudo chown -R ${env_vars[PUID]}:${env_vars[PGID]} "$hp"
  fi
done

cd "$svc_dir"

# Generate run.sh with clean output and automatic container removal
cat > run.sh << 'EOF_RUNSH'
#!/bin/sh
set -e

# Initialize TS_NAME with a unique name for this Tailscale instance
TS_NAME="SERVICE_NAME"

# Automatically remove existing containers for this service only
echo "Removing existing SERVICE_NAME containers..."
podman rm -f SERVICE_NAME 2>/dev/null || true
podman rm -f npm-SERVICE_NAME 2>/dev/null || true
podman rm -f tailscale-SERVICE_NAME 2>/dev/null || true

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

# Start main service
echo "Starting SERVICE_NAME..."
podman ps --format '{{.Names}}' | grep -q "^SERVICE_NAME$" || podman run -d \
  --name SERVICE_NAME \
EOF_RUNSH

# Add network configuration based on Tailscale inclusion
if [[ "$include_ts" == "yes" ]]; then
  cat >> run.sh << 'EOF_NETWORK'
  --network container:tailscale-SERVICE_NAME \
EOF_NETWORK
fi

# Add environment variables
for k in "${env_keys[@]}"; do
  echo "  -e $k=\"${env_vars[$k]}\" \\" >> run.sh
done

# Add volume mounts
for v in "${vol_keys[@]}"; do
  echo "  -v ${volumes_map[$v]}:$v \\" >> run.sh
done

# Complete the service container command
cat >> run.sh << 'EOF_RESTART'
  --restart RESTART_POLICY \
  SERVICE_IMAGE

echo "Waiting for SERVICE_NAME..."
sleep 10

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

EOF_RESTART

if [[ "$include_npm" == "yes" ]]; then
  cat >> run.sh << 'EOF_NPM_CHECK'
# Check NPM connectivity
NPM_READY=$(podman exec tailscale-SERVICE_NAME wget -q --spider --timeout=5 http://localhost:81 2>/dev/null && echo "yes" || echo "no")
EOF_NPM_CHECK
fi

if [[ -n "$primary_port" ]]; then
  cat >> run.sh << 'EOF_SERVICE_CHECK'
# Check service connectivity  
SERVICE_READY=$(podman exec tailscale-SERVICE_NAME wget -q --spider --timeout=5 http://localhost:PRIMARY_PORT 2>/dev/null && echo "yes" || echo "no")
EOF_SERVICE_CHECK
fi

# Complete the display section
cat >> run.sh << 'EOF_DISPLAY'
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
EOF_DISPLAY

if [[ "$include_npm" == "yes" ]]; then
  cat >> run.sh << 'EOF_NPM_STATUS'
if [ "$NPM_READY" = "yes" ]; then
  echo "  Nginx Proxy Manager: ✓ Ready"
else
  echo "  Nginx Proxy Manager: × Not ready"
fi
EOF_NPM_STATUS
fi

if [[ -n "$primary_port" ]]; then
  cat >> run.sh << 'EOF_SERVICE_STATUS'
if [ "$SERVICE_READY" = "yes" ]; then
  echo "  SERVICE_NAME: ✓ Ready"
else
  echo "  SERVICE_NAME: × Not ready"
fi
EOF_SERVICE_STATUS
fi

# Finish the display section
cat >> run.sh << 'EOF_URLS'
echo ""
echo "Access URLs:"
EOF_URLS

if [[ "$include_npm" == "yes" ]]; then
  cat >> run.sh << 'EOF_NPM_URL'
echo "  NPM Admin: http://$TS_FQDN:81"
EOF_NPM_URL
fi

if [[ -n "$primary_port" ]]; then
  cat >> run.sh << 'EOF_SERVICE_URL'
echo "  SERVICE_NAME: http://$TS_FQDN:PRIMARY_PORT"
EOF_SERVICE_URL
fi

# Add multiple port information if needed
if [[ ${#port_keys[@]} -gt 1 ]]; then
  cat >> run.sh << 'EOF_ALL_PORTS'
echo ""
echo "Additional Ports:"
EOF_ALL_PORTS
  
  for p in "${port_keys[@]:1}"; do
    if [[ -n "$p" ]]; then
      cat >> run.sh << EOF_PORT
echo "  - Port $p: http://\$TS_FQDN:$p"
EOF_PORT
    fi
  done
fi

# Finish the script
cat >> run.sh << 'EOF_FINAL'
echo ""
echo "Direct IP Access:"
echo "  http://$TS_IP:81 (NPM)"
EOF_FINAL

if [[ -n "$primary_port" ]]; then
  cat >> run.sh << 'EOF_PRIMARY_IP'
echo "  http://$TS_IP:PRIMARY_PORT (SERVICE_NAME)"
EOF_PRIMARY_IP
fi

cat >> run.sh << 'EOF_END'
echo ""

if [ "$SERVICE_READY" != "yes" ]; then
  echo "Note: SERVICE_NAME is not yet accessible."
  echo "Run './diagnose.sh' if the issue persists."
fi
EOF_END

# Replace all placeholders in run.sh using | as delimiter to avoid conflicts
sed -i "s|SERVICE_NAME|$service|g" run.sh
sed -i "s|AUTH_KEY|$auth_key|g" run.sh
sed -i "s|TAILSCALE_IMAGE|$ts_image|g" run.sh
sed -i "s|NPM_IMAGE|$npm_image|g" run.sh
sed -i "s|RESTART_POLICY|$restart_policy|g" run.sh
sed -i "s|SERVICE_IMAGE|$service_image|g" run.sh
sed -i "s|PRIMARY_PORT|$primary_port|g" run.sh

chmod +x run.sh

# Create stop.sh
cat > stop.sh << EOF
#!/bin/sh
set -e
echo "Stopping services..."
podman stop $service 2>/dev/null || true
[ "$include_npm" = "yes" ] && podman stop npm-$service 2>/dev/null || true
[ "$include_ts" = "yes" ] && podman stop tailscale-$service 2>/dev/null || true
echo "All services stopped"
EOF
chmod +x stop.sh

# Create remove.sh
cat > remove.sh << EOF
#!/bin/sh
set -e
echo "Removing services..."
podman rm -f $service 2>/dev/null || true
[ "$include_npm" = "yes" ] && podman rm -f npm-$service 2>/dev/null || true
[ "$include_ts" = "yes" ] && podman rm -f tailscale-$service 2>/dev/null || true
echo "All services removed"
echo "To reclaim ownership of volumes: sudo chown -R \\\$USER:\\\$USER ."
EOF
chmod +x remove.sh

# Create clean diagnose.sh
cat > diagnose.sh << 'EOF_DIAGNOSE'
#!/bin/sh
set -e

SERVICE_NAME="SERVICE_NAME_REPLACE"

echo "=== $SERVICE_NAME Diagnostic Tool ==="
echo ""

# 1. Container status
echo "Container Status:"
echo "----------------"
CONTAINERS=$(podman ps -a --format '{{.Names}} {{.Status}}' | grep -E "($SERVICE_NAME|tailscale-$SERVICE_NAME|npm-$SERVICE_NAME)")
if [ -n "$CONTAINERS" ]; then
  echo "$CONTAINERS"
else
  echo "No $SERVICE_NAME containers found"
fi
echo ""

# 2. Tailscale status
if podman ps --format '{{.Names}}' | grep -q "^tailscale-$SERVICE_NAME$"; then
  echo "Tailscale Status:"
  echo "----------------"
  TS_IP=$(podman exec tailscale-$SERVICE_NAME tailscale ip -4 2>/dev/null || echo "Not available")
  echo "IP: $TS_IP"
  
  # Get hostname properly
  TS_HOSTNAME=$(podman exec tailscale-$SERVICE_NAME tailscale status --self 2>/dev/null | head -1 | awk '{print $2}' || echo "")
  if [ -n "$TS_HOSTNAME" ]; then
    echo "Hostname: $TS_HOSTNAME"
    echo "FQDN: ${TS_HOSTNAME}.ts.net"
  fi
  echo ""
fi

# 3. Service logs
if podman ps --format '{{.Names}}' | grep -q "^$SERVICE_NAME$"; then
  echo "Recent $SERVICE_NAME logs:"
  echo "------------------------"
  podman logs --tail 10 $SERVICE_NAME
  echo ""
fi

# 4. Binding check
if podman ps --format '{{.Names}}' | grep -q "^$SERVICE_NAME$"; then
  echo "Binding Configuration:"
  echo "---------------------"
  if podman exec $SERVICE_NAME sh -c "[ -f /config/config.xml ]" 2>/dev/null; then
    BIND_ADDRESS=$(podman exec $SERVICE_NAME grep -oP '(?<=<BindAddress>)[^<]+' /config/config.xml 2>/dev/null || echo "Not found")
    echo "Bind Address: $BIND_ADDRESS"
    
    if [ "$BIND_ADDRESS" = "127.0.0.1" ]; then
      echo ""
      echo "⚠️  Warning: Service is binding to localhost only"
      echo "This will prevent Tailscale access"
      echo ""
      echo "Fix by running:"
      echo "podman exec $SERVICE_NAME sed -i 's/<BindAddress>127.0.0.1</<BindAddress>*</g' /config/config.xml"
      echo "podman restart $SERVICE_NAME"
    fi
  else
    echo "No config.xml found"
  fi
  echo ""
fi

# 5. Connectivity test
if podman ps --format '{{.Names}}' | grep -q "^tailscale-$SERVICE_NAME$"; then
  echo "Connectivity Test:"
  echo "-----------------"
  
  # Test NPM
  NPM_TEST=$(podman exec tailscale-$SERVICE_NAME sh -c "command -v wget >/dev/null 2>&1 || apk add --no-cache wget >/dev/null 2>&1; wget -q --spider --timeout=5 http://localhost:81" && echo "NPM: ✓ Accessible" || echo "NPM: × Not accessible")
  echo "$NPM_TEST"
  
  # Test service if port is defined
  if [ -n "PRIMARY_PORT_REPLACE" ]; then
    SVC_TEST=$(podman exec tailscale-$SERVICE_NAME wget -q --spider --timeout=5 http://localhost:PRIMARY_PORT_REPLACE 2>/dev/null && echo "$SERVICE_NAME: ✓ Accessible" || echo "$SERVICE_NAME: × Not accessible")
    echo "$SVC_TEST"
  fi
fi
echo ""

echo "Troubleshooting Tips:"
echo "--------------------"
echo "1. Restart services: ./stop.sh && ./run.sh"
echo "2. Check logs: podman logs $SERVICE_NAME"
echo "3. Remove and recreate: ./remove.sh && ./run.sh"
EOF_DIAGNOSE

# Replace placeholders in diagnose.sh using | as delimiter
sed -i "s|SERVICE_NAME_REPLACE|$service|g" diagnose.sh
sed -i "s|PRIMARY_PORT_REPLACE|$primary_port|g" diagnose.sh

chmod +x diagnose.sh

# Display summary and instructions
echo "Generated scripts in $svc_dir:"
echo "- run.sh: Start the service with all dependencies"
echo "- stop.sh: Stop all containers"
echo "- remove.sh: Remove all containers"
echo "- diagnose.sh: Troubleshoot issues"
echo ""
echo "To start the service: cd $svc_dir && ./run.sh"
