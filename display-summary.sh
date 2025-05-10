#!/usr/bin/env bash

# Display deployment summary
display_service_summary() {
    local service_info="$1"
    
    # Extract information
    local service=$(jq -r '.service' <<<"$service_info")
    local service_dir=$(jq -r '.service_dir' <<<"$service_info")
    
    log_section "Deployment Summary"
    
    display_service_overview "$service_info"
    display_generated_files "$service_dir"
    display_usage_instructions "$service_dir"
    display_access_info "$service_info"
    
    log_success "Service $service deployed successfully!"
}

# Display service overview
display_service_overview() {
    local service_info="$1"
    
    local service=$(jq -r '.service' <<<"$service_info")
    local image=$(jq -r '.image' <<<"$service_info")
    local include_ts=$(jq -r '.include_tailscale' <<<"$service_info")
    local include_npm=$(jq -r '.include_npm' <<<"$service_info")
    
    echo ""
    echo "Service Overview:"
    echo "----------------"
    echo "  Name: $service"
    echo "  Image: $image"
    echo "  Tailscale: $include_ts"
    echo "  NPM: $include_npm"
}

# Display generated files
display_generated_files() {
    local service_dir="$1"
    
    echo ""
    echo "Generated Files in $service_dir:"
    echo "---------------------------------"
    
    local files=()
    if [[ -f "$service_dir/run.sh" ]]; then
        files+=("✓ run.sh: Start the service with all dependencies")
    fi
    if [[ -f "$service_dir/stop.sh" ]]; then
        files+=("✓ stop.sh: Stop all containers")
    fi
    if [[ -f "$service_dir/remove.sh" ]]; then
        files+=("✓ remove.sh: Remove all containers")
    fi
    if [[ -f "$service_dir/diagnose.sh" ]]; then
        files+=("✓ diagnose.sh: Troubleshoot issues")
    fi
    
    for file in "${files[@]}"; do
        echo "  $file"
    done
}

# Display usage instructions
display_usage_instructions() {
    local service_dir="$1"
    
    echo ""
    echo "Usage Instructions:"
    echo "-------------------"
    echo "  To start the service:"
    echo "    cd $service_dir && ./run.sh"
    echo ""
    echo "  To stop the service:"
    echo "    cd $service_dir && ./stop.sh"
    echo ""
    echo "  To remove containers:"
    echo "    cd $service_dir && ./remove.sh"
    echo ""
    echo "  To diagnose issues:"
    echo "    cd $service_dir && ./diagnose.sh"
}

# Display access information
display_access_info() {
    local service_info="$1"
    
    local service=$(jq -r '.service' <<<"$service_info")
    local include_ts=$(jq -r '.include_tailscale' <<<"$service_info")
    local include_npm=$(jq -r '.include_npm' <<<"$service_info")
    local primary_port=$(jq -r '.primary_port' <<<"$service_info")
    
    echo ""
    echo "Access Information:"
    echo "------------------"
    
    if [[ "$include_ts" == "yes" ]]; then
        echo "  Once deployed, the service will be accessible via Tailscale:"
        
        if [[ "$include_npm" == "yes" ]]; then
            echo "    NPM Admin: http://${service}.ts.net:81"
        fi
        
        if [[ -n "$primary_port" ]]; then
            echo "    $service: http://${service}.ts.net:$primary_port"
        fi
        
        echo ""
        echo "  Note: The exact hostname will be displayed after running ./run.sh"
    else
        echo "  Service will be accessible via local network only"
        if [[ -n "$primary_port" ]]; then
            echo "    Port: $primary_port"
        fi
    fi
}

# Display troubleshooting information
display_troubleshooting_info() {
    echo ""
    echo "Troubleshooting:"
    echo "---------------"
    echo "  1. Check logs with: podman logs <container_name>"
    echo "  2. Use diagnose.sh for comprehensive diagnostics"
    echo "  3. Restart services with: ./stop.sh && ./run.sh"
    echo "  4. Full reset with: ./remove.sh && ./run.sh"
}

# Display configuration summary
display_configuration_summary() {
    local service_info="$1"
    
    echo ""
    echo "Configuration Summary:"
    echo "---------------------"
    
    # Environment variables
    echo "  Environment Variables:"
    jq -r '.environment | to_entries[] | "    \(.key)=\(.value)"' <<<"$service_info"
    
    # Volumes
    echo "  Volume Mappings:"
    jq -r '.volumes | to_entries[] | "    \(.value) → \(.key)"' <<<"$service_info"
    
    # Ports
    echo "  Port Mappings:"
    jq -r '.ports | to_entries[] | "    \(.value) → \(.key)"' <<<"$service_info"
}

# Final deployment message
display_final_message() {
    local service_dir="$1"
    
    echo ""
    echo "=========================================="
    echo "  Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "To start your service:"
    echo "  cd $service_dir && ./run.sh"
    echo ""
}
