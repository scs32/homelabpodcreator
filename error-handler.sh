#!/usr/bin/env bash

# Global error handling configuration
ERROR_LOG_FILE="${ERROR_LOG_FILE:-./.error.log}"

# Function to setup error handler
setup_error_handler() {
    # Trap any unhandled errors
    trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR
    
    # Ensure error log exists
    touch "$ERROR_LOG_FILE"
}

# Main error handler function
handle_error() {
    local exit_code=$1
    local line_number=$2
    local bash_line_number=$3
    local command=$4
    local functions="${5:-}"
    
    # Format the error message
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to error log
    {
        echo "==== ERROR OCCURRED ===="
        echo "Timestamp: $timestamp"
        echo "Exit Code: $exit_code"
        echo "Line Number: $line_number"
        echo "Bash Line Number: $bash_line_number"
        echo "Command: $command"
        echo "Function Stack: $functions"
        echo "Script: ${BASH_SOURCE[1]}"
        echo "======================="
    } >> "$ERROR_LOG_FILE"
    
    # Display user-friendly error message
    echo "❌ Error occurred in ${BASH_SOURCE[1]} at line $line_number" >&2
    echo "Command: $command" >&2
    echo "Exit code: $exit_code" >&2
    echo "Full details logged to: $ERROR_LOG_FILE" >&2
    
    # Clean up if needed
    cleanup_on_error
    
    exit $exit_code
}

# Function to handle cleanup on errors
cleanup_on_error() {
    # Remove any partial files created
    rm -f ./.last-config.json.tmp
    
    # You can add more cleanup here as needed
}

# Function for safe execution with error context
safe_execute() {
    local command="$1"
    local description="${2:-executing command}"
    
    echo "Attempting: $description..."
    if ! eval "$command"; then
        echo "Failed: $description" >&2
        return 1
    fi
    echo "Completed: $description"
}

# Function to check required dependencies
check_required_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $name is required but not installed" >&2
        return 1
    fi
}

# Function to validate file existence
check_required_file() {
    local file="$1"
    local description="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: Required $description not found: $file" >&2
        return 1
    fi
}

# Function to validate directory
ensure_directory() {
    local dir="$1"
    local description="${2:-directory}"
    
    if [[ ! -d "$dir" ]]; then
        echo "Creating $description: $dir"
        mkdir -p "$dir" || {
            echo "Failed to create $description: $dir" >&2
            return 1
        }
    fi
}
