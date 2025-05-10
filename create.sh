#!/usr/bin/env bash
set -euo pipefail

# Load utilities
source ./error-handler.sh
source ./logging-utils.sh

# Main entry point for service creation
main() {
    setup_error_handler
    
    log_info "Starting service deployment..."
    
    # Read configuration from stdin
    local config_json
    config_json="$(cat)"
    
    if [[ -z "$config_json" ]]; then
        log_error "No JSON input provided"
        exit 1
    fi
    
    # Save config for debugging
    echo "$config_json" > ./.last-config.json
    
    # Parse basic service info
    source ./parse-service-config.sh
    local service_info
    service_info=$(parse_service_config "$config_json")
    
    # Create service directory structure
    source ./setup-service-env.sh
    setup_service_environment "$service_info"
    
    # Generate all management scripts
    source ./generate-scripts.sh
    generate_all_scripts "$service_info"
    
    # Display completion message
    source ./display-summary.sh
    display_service_summary "$service_info"
    
    log_info "Service deployment completed successfully"
}

# Call main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
