#!/usr/bin/env bash

# Setup service environment (directories, permissions, etc.)
setup_service_environment() {
    local service_info="$1"
    
    log_section "Setting Up Service Environment"
    
    # Extract necessary information
    local service_dir
    local volumes_json
    local env_vars_json
    local include_npm
    local include_ts
    local puid
    local pgid
    
    service_dir=$(jq -r '.service_dir' <<<"$service_info")
    volumes_json=$(jq -c '.volumes' <<<"$service_info")
    env_vars_json=$(jq -c '.environment' <<<"$service_info")
    include_npm=$(jq -r '.include_npm' <<<"$service_info")
    include_ts=$(jq -r '.include_tailscale' <<<"$service_info")
    puid=$(jq -r '.environment.PUID // ""' <<<"$service_info")
    pgid=$(jq -r '.environment.PGID // ""' <<<"$service_info")
    
    # Create main service directory
    log_info "Creating service directory: $service_dir"
    ensure_directory "$service_dir" "service directory"
    
    # Create NPM directories if needed
    if [[ "$include_npm" == "yes" ]]; then
        log_info "Setting up NPM directories"
        ensure_directory "$service_dir/npm/data" "NPM data directory"
        ensure_directory "$service_dir/npm/letsencrypt" "NPM letsencrypt directory"
    fi
    
    # Create Tailscale state directory if needed
    if [[ "$include_ts" == "yes" ]]; then
        log_info "Setting up Tailscale directory"
        ensure_directory "$service_dir/tailscale" "Tailscale state directory"
    fi
    
    # Create volume directories
    log_info "Creating volume directories"
    create_volume_directories "$volumes_json" "$puid" "$pgid"
    
    # Set working directory
    cd "$service_dir"
    log_info "Changed to service directory: $service_dir"
}

# Create all volume directories with proper ownership
create_volume_directories() {
    local volumes_json="$1"
    local puid="${2:-}"
    local pgid="${3:-}"
    
    # Get all host paths from volumes
    local host_paths
    readarray -t host_paths < <(jq -r '.[]' <<<"$volumes_json")
    
    for host_path in "${host_paths[@]}"; do
        if [[ -n "$host_path" ]]; then
            log_info "Creating volume directory: $host_path"
            ensure_directory "$host_path" "volume directory"
            
            # Set ownership if PUID/PGID are provided
            if [[ -n "$puid" && -n "$pgid" ]]; then
                set_directory_ownership "$host_path" "$puid" "$pgid"
            fi
        fi
    done
}

# Set ownership on a directory
set_directory_ownership() {
    local path="$1"
    local puid="$2"
    local pgid="$3"
    
    log_debug "Setting ownership on $path to $puid:$pgid"
    
    # Try without sudo first
    if chown -R "${puid}:${pgid}" "$path" 2>/dev/null; then
        log_success "Ownership set successfully"
    else
        # Fall back to sudo
        log_warn "Trying with sudo..."
        if sudo chown -R "${puid}:${pgid}" "$path"; then
            log_success "Ownership set with sudo"
        else
            log_error "Failed to set ownership on $path"
            return 1
        fi
    fi
}

# Verify service directory setup
verify_environment_setup() {
    local service_dir="$1"
    local include_npm="$2"
    local include_ts="$3"
    
    log_info "Verifying environment setup"
    
    # Check main directory
    if [[ ! -d "$service_dir" ]]; then
        log_error "Service directory not found: $service_dir"
        return 1
    fi
    
    # Check NPM directories
    if [[ "$include_npm" == "yes" ]]; then
        if [[ ! -d "$service_dir/npm/data" ]] || [[ ! -d "$service_dir/npm/letsencrypt" ]]; then
            log_error "NPM directories not properly created"
            return 1
        fi
    fi
    
    # Check Tailscale directory
    if [[ "$include_ts" == "yes" ]]; then
        if [[ ! -d "$service_dir/tailscale" ]]; then
            log_error "Tailscale directory not found"
            return 1
        fi
    fi
    
    log_success "Environment setup verified"
}

# Clean up environment on error
cleanup_environment() {
    local service_dir="$1"
    
    log_warn "Cleaning up environment due to error"
    
    # Remove service directory if it's empty
    if [[ -d "$service_dir" ]]; then
        local file_count
        file_count=$(find "$service_dir" -type f | wc -l)
        
        if [[ $file_count -eq 0 ]]; then
            log_info "Removing empty service directory: $service_dir"
            rmdir "$service_dir" 2>/dev/null || true
        else
            log_warn "Service directory not empty, skipping cleanup"
        fi
    fi
}

# Display environment summary
display_environment_summary() {
    local service_info="$1"
    
    local service_dir
    local service
    local include_npm
    local include_ts
    
    service_dir=$(jq -r '.service_dir' <<<"$service_info")
    service=$(jq -r '.service' <<<"$service_info")
    include_npm=$(jq -r '.include_npm' <<<"$service_info")
    include_ts=$(jq -r '.include_tailscale' <<<"$service_info")
    
    log_section "Environment Summary"
    log_info "Service: $service"
    log_info "Directory: $service_dir"
    log_info "NPM included: $include_npm"
    log_info "Tailscale included: $include_ts"
    
    # List created directories
    if [[ -d "$service_dir" ]]; then
        echo "Created directories:"
        find "$service_dir" -type d | sort | sed 's/^/  /'
    fi
}
