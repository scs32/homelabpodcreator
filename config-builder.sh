#!/usr/bin/env bash

# Configuration builder for HomePod Creator
# Assembles the final JSON configuration from user inputs

# Function to build the final configuration JSON
build_configuration() {
    local json_file="$1"
    local service_name="$2"
    local npm_choice="$3"
    local tailscale_choice="$4"
    local auth_key="$5"
    local base_path="$6"
    
    # Get service specification from homelab.js
    local spec
    spec=$(jq -c --arg name "$service_name" \
        '.[] | select(.name == $name)' "$json_file")
    
    # Extract service details
    local image
    local ports
    local restart_policy
    local default_network
    local network_mode
    
    image=$(jq -r '.image' <<<"$spec")
    ports=$(jq '.ports' <<<"$spec")
    restart_policy=$(jq -r '.restart_policy' <<<"$spec")
    default_network=$(jq -r '.network_mode' <<<"$spec")
    
    # Determine network mode based on Tailscale choice
    if [[ "$tailscale_choice" == "yes" ]]; then
        network_mode="service:tailscale-$service_name"
    else
        network_mode="$default_network"
    fi
    
    # Create a temporary file for the configuration
    local tmp_config
    tmp_config="$(mktemp)"
    
    # Build the configuration JSON
    {
        printf '{\n'
        printf '  "container": "%s",\n' "$service_name"
        printf '  "image": "%s",\n' "$image"
        printf '  "network_mode": "%s",\n' "$network_mode"
        printf '  "ports": %s,\n' "$ports"
        printf '  "restart_policy": "%s",\n' "$restart_policy"
        printf '  "include_npm": "%s",\n' "$npm_choice"
        printf '  "include_tailscale": "%s",\n' "$tailscale_choice"
        printf '  "auth_key": "%s",\n' "$auth_key"
        printf '  "base_path": "%s",\n' "$base_path"
        printf '  "environment": {\n'
        
        # Add environment variables
        add_environment_to_config
        
        printf '  },\n'
        printf '  "volumes": {\n'
        
        # Add volumes
        add_volumes_to_config
        
        printf '  }\n'
        printf '}\n'
    } > "$tmp_config"
    
    # Display the configuration
    tee "$tmp_config" < "$tmp_config"
    echo "$tmp_config"
}

# Helper function to add environment variables to config
add_environment_to_config() {
    local env_count=0
    local total_vars=${#env_keys[@]}
    
    for key in "${env_keys[@]}"; do
        value="${ENV_VARS[$key]}"
        ((env_count++))
        
        # Add comma except for last item
        if [[ $env_count -lt $total_vars ]]; then
            printf '    "%s": "%s",\n' "$key" "$value"
        else
            printf '    "%s": "%s"\n' "$key" "$value"
        fi
    done
}

# Helper function to add volumes to config
add_volumes_to_config() {
    local vol_count=0
    local total_vols=${#vol_keys[@]}
    
    for container_path in "${vol_keys[@]}"; do
        host_path="${VOLUMES[$container_path]}"
        ((vol_count++))
        
        # Add comma except for last item
        if [[ $vol_count -lt $total_vols ]]; then
            printf '    "%s": "%s",\n' "$container_path" "$host_path"
        else
            printf '    "%s": "%s"\n' "$container_path" "$host_path"
        fi
    done
}

# Function to validate configuration
validate_configuration() {
    local config_file="$1"
    
    # Check if file exists and is valid JSON
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    if ! jq empty "$config_file" 2>/dev/null; then
        return 1
    fi
    
    # Validate required fields
    local required_fields=(
        "container"
        "image"
        "network_mode"
        "restart_policy"
        "include_npm"
        "include_tailscale"
        "auth_key"
        "base_path"
    )
    
    for field in "${required_fields[@]}"; do
        if [[ $(jq -r ".$field" "$config_file") == "null" ]]; then
            echo "Error: Missing required field: $field"
            return 1
        fi
    done
    
    return 0
}

# Function to save configuration for later use
save_configuration() {
    local config_file="$1"
    local service_name="$2"
    local save_dir="${3:-$HOME/Pods/.configs}"
    
    # Create save directory if it doesn't exist
    mkdir -p "$save_dir"
    
    # Save with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local save_path="$save_dir/${service_name}_${timestamp}.json"
    
    cp "$config_file" "$save_path"
    echo "Configuration saved to: $save_path"
}

# Function to load saved configuration
load_configuration() {
    local service_name="$1"
    local config_dir="${2:-$HOME/Pods/.configs}"
    
    # Find most recent configuration for service
    local config_file
    config_file=$(find "$config_dir" -name "${service_name}_*.json" -type f -printf '%T@ %p\n' 2>/dev/null | \
                 sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        echo "$config_file"
        return 0
    else
        return 1
    fi
}

# Function to display configuration summary
display_config_summary() {
    local config_file="$1"
    
    echo ""
    echo "=== Configuration Summary ==="
    echo "Service: $(jq -r '.container' "$config_file")"
    echo "Image: $(jq -r '.image' "$config_file")"
    echo "NPM: $(jq -r '.include_npm' "$config_file")"
    echo "Tailscale: $(jq -r '.include_tailscale' "$config_file")"
    echo "Network: $(jq -r '.network_mode' "$config_file")"
    echo "Base Path: $(jq -r '.base_path' "$config_file")"
    echo ""
    echo "Environment Variables:"
    jq -r '.environment | to_entries[] | "  \(.key)=\(.value)"' "$config_file"
    echo ""
    echo "Volume Mappings:"
    jq -r '.volumes | to_entries[] | "  \(.value) → \(.key)"' "$config_file"
    echo "=========================="
}
