#!/usr/bin/env bash

# User interface component for HomePod Creator
# Handles all interactive prompts and user input

# Formatting
BOLD=$'\e[1m'
NC=$'\e[0m'

# Function to select a container
select_container() {
    local json_file="$1"
    
    # Load available containers
    mapfile -t RAW_NAMES < <(jq -r '.[].name' "$json_file")
    NORMALIZED_NAMES=()
    for name in "${RAW_NAMES[@]}"; do
        lc="${name,,}"
        NORMALIZED_NAMES+=("${lc^}")
    done
    
    # Display menu
    printf "\n%d Available Containers:\n\n" "${#NORMALIZED_NAMES[@]}"
    for i in "${!NORMALIZED_NAMES[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${NORMALIZED_NAMES[i]}"
    done
    
    # Get selection
    printf "\nSelect a container (1-%d): " "${#NORMALIZED_NAMES[@]}"
    read -r SEL
    [[ "$SEL" == "q" ]] && return 1
    printf "\n"
    
    # Validate selection
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#NORMALIZED_NAMES[@]} )); then
        printf "Invalid selection.\n\n"
        return 1
    fi
    
    IDX=$((SEL-1))
    SELECTED_RAW_NAME="${RAW_NAMES[IDX]}"
    SELECTED_NORMALIZED_NAME="${NORMALIZED_NAMES[IDX]}"
    printf "You selected: %s (%s)\n\n" "$SELECTED_NORMALIZED_NAME" "$SELECTED_RAW_NAME"
    
    # Export for use by other scripts
    echo "$SELECTED_RAW_NAME"
}

# Function to ask yes/no questions
ask_yes_no() {
    local question="$1"
    local default="${2:-yes}"
    local answer=""
    
    if [[ "$default" == "yes" ]]; then
        printf "$question (%syes%s/%sno%s): " "$BOLD" "$NC" "$BOLD" "$NC"
    else
        printf "$question (%sno%s/%syes%s): " "$BOLD" "$NC" "$BOLD" "$NC"
    fi
    
    read -r answer
    [[ "$answer" == "q" ]] && return 2
    answer="${answer:-$default}"
    printf "\n"
    
    if ! [[ "$answer" =~ ^(yes|no)$ ]]; then
        printf "Invalid input. Please answer yes or no.\n\n"
        return 1
    fi
    
    printf "%s: %s%s%s\n\n" "${question%%?}" "$BOLD" "$answer" "$NC"
    echo "$answer"
}

# Function to get text input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local value=""
    
    printf "%s (%s%s%s): " "$prompt" "$BOLD" "$default" "$NC"
    read -r value
    [[ "$value" == "q" ]] && return 2
    value="${value:-$default}"
    printf "\nUsing: %s\n\n" "$value"
    
    echo "$value"
}

# Function to collect environment variables
collect_env_vars() {
    local json_file="$1"
    local service_name="$2"
    
    # Get default environment variables
    ENV_JSON=$(jq -c --arg name "$service_name" \
        '.[] | select(.name == $name).environment' "$json_file")
    
    declare -gA ENV_VARS
    while IFS=" " read -r k v; do
        ENV_VARS["$k"]="$v"
    done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$ENV_JSON")
    
    # Collect user input for each variable
    for key in "${!ENV_VARS[@]}"; do
        default="${ENV_VARS[$key]}"
        printf "Enter %s (%s%s%s): " "$key" "$BOLD" "$default" "$NC"
        read -r val
        [[ "$val" == "q" ]] && return 1
        ENV_VARS["$key"]="${val:-$default}"
        printf "\n"
    done
    
    # Export the keys for use by other scripts
    env_keys=("${!ENV_VARS[@]}")
    printf '%s\n' "${env_keys[@]}"
}

# Function to collect volume mappings
collect_volumes() {
    local json_file="$1"
    local service_name="$2"
    local base_path="$3"
    
    # Get default volume mappings
    mapfile -t CONTAINER_PATHS < <(jq -r --arg name "$service_name" \
        '.[] | select(.name == $name).volumes | to_entries[].value' "$json_file")
    
    declare -gA VOLUMES
    for cp in "${CONTAINER_PATHS[@]}"; do
        sub="${cp#/}"
        default_host="$base_path/$service_name/$sub"
        printf "Host path for %s (%s%s%s): " "$cp" "$BOLD" "$default_host" "$NC"
        read -r h
        [[ "$h" == "q" ]] && return 1
        VOLUMES["$cp"]="${h:-$default_host}"
        printf "\n"
    done
    
    # Ask for additional volumes
    printf "Would you like to add more volumes? [%sno%s/%syes%s]: " "$BOLD" "$NC" "$BOLD" "$NC"
    read -r MORE
    [[ "$MORE" == "q" ]] && return 1
    MORE="${MORE:-no}"
    printf "\n"
    
    if [[ "$MORE" == "yes" ]]; then
        while true; do
            printf "Enter additional container path: "
            read -r cp; [[ "$cp" == "q" ]] && return 1
            printf "Enter host path for %s: " "$cp"
            read -r hp; [[ "$hp" == "q" ]] && return 1
            VOLUMES["$cp"]="$hp"
            printf "\n"
            printf "More volumes? [%sno%s/%syes%s]: " "$BOLD" "$NC" "$BOLD" "$NC"
            read -r MORE; [[ "$MORE" == "q" ]] && return 1
            MORE="${MORE:-no}"
            printf "\n"
            [[ "$MORE" != "yes" ]] && break
        done
    fi
    
    # Export the volume keys for use by other scripts
    vol_keys=("${!VOLUMES[@]}")
    printf '%s\n' "${vol_keys[@]}"
}

# Function to display and confirm configuration
confirm_configuration() {
    local config_json="$1"
    
    printf "\nThe following will be used to create a pod:\n\n"
    cat "$config_json"
    printf "\n"
    
    while true; do
        printf "Would you like to continue? (yes/no): "
        read -r CONT
        if [[ "$CONT" == "q" ]]; then
            return 1
        elif [[ "$CONT" == "yes" ]]; then
            return 0
        elif [[ "$CONT" == "no" ]]; then
            printf "Aborted.\n"
            return 1
        else
            printf "Please answer yes or no.\n\n"
        fi
    done
}

# Function to get Tailscale auth key with file support
get_auth_key() {
    local default_file="${1:-$HOME/Pods/.tailscale_authkey}"
    local default_key=""
    
    if [[ -f "$default_file" ]]; then
        default_key="$(<"$default_file")"
        default_key="${default_key//$'\n'/}"
    fi
    
    printf "Auth key (%s%s%s): " "$BOLD" "$default_key" "$NC"
    read -r INPUT_KEY
    [[ "$INPUT_KEY" == "q" ]] && return 1
    AUTH_KEY="${INPUT_KEY:-$default_key}"
    printf "\nUsing auth key: %s\n\n" "$AUTH_KEY"
    
    echo "$AUTH_KEY"
}
