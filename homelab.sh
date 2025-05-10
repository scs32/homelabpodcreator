#!/usr/bin/env bash
set -euo pipefail

# Formatting
BOLD=$'\e[1m'
NC=$'\e[0m'

# Locate this script and the spec file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="$SCRIPT_DIR/homelab.js"

# Defaults
TS_AUTHKEY_FILE="${TS_AUTHKEY_FILE:-$HOME/Pods/.tailscale_authkey}"
DEFAULT_BASE_PATH="${BASE_PATH:-$HOME/Pods}"

# Dependency check
command -v jq >/dev/null || { printf "Error: jq is required but not installed\n"; exit 1; }
[[ -f "$JSON_FILE" ]] || { printf "Error: homelab.js not found in %s\n" "$SCRIPT_DIR"; exit 1; }

# --- STEP 1: CONTAINER SELECTION ---
mapfile -t RAW_NAMES < <(jq -r '.[].name' "$JSON_FILE")
NORMALIZED_NAMES=()
for name in "${RAW_NAMES[@]}"; do
  lc="${name,,}"
  NORMALIZED_NAMES+=("${lc^}")
done

printf "\n%d Available Containers:\n\n" "${#NORMALIZED_NAMES[@]}"
for i in "${!NORMALIZED_NAMES[@]}"; do
  printf "%2d) %s\n" $((i+1)) "${NORMALIZED_NAMES[i]}"
done

printf "\nSelect a container (1-%d): " "${#NORMALIZED_NAMES[@]}"
read -r SEL
[[ "$SEL" == "q" ]] && exit 0
printf "\n"
if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#NORMALIZED_NAMES[@]} )); then
  printf "Invalid selection.\n\n"; exit 1
fi
IDX=$((SEL-1))
SELECTED_RAW_NAME="${RAW_NAMES[IDX]}"
SELECTED_NORMALIZED_NAME="${NORMALIZED_NAMES[IDX]}"
printf "You selected: %s (%s)\n\n" "$SELECTED_NORMALIZED_NAME" "$SELECTED_RAW_NAME"

# --- STEP 1.5: NPM PACKAGING ---
printf "Would you like to package this with NPM? (%syes%s/%sno%s): " "$BOLD" "$NC" "$BOLD" "$NC"
read -r INCLUDE_NPM
[[ "$INCLUDE_NPM" == "q" ]] && exit 0
INCLUDE_NPM="${INCLUDE_NPM:-yes}"
printf "\n"
if ! [[ "$INCLUDE_NPM" =~ ^(yes|no)$ ]]; then
  printf "Invalid input. Please answer yes or no.\n\n"; exit 1
fi
printf "Packaging with NPM: %s%s%s\n\n" "$BOLD" "$INCLUDE_NPM" "$NC"

# --- STEP 1.6: TAILSCALE USAGE ---
printf "Would you like to enable Tailscale? (%syes%s/%sno%s): " "$BOLD" "$NC" "$BOLD" "$NC"
read -r INCLUDE_TS
[[ "$INCLUDE_TS" == "q" ]] && exit 0
INCLUDE_TS="${INCLUDE_TS:-yes}"
printf "\n"
if ! [[ "$INCLUDE_TS" =~ ^(yes|no)$ ]]; then
  printf "Invalid input. Please answer yes or no.\n\n"; exit 1
fi
printf "Tailscale enabled: %s%s%s\n\n" "$BOLD" "$INCLUDE_TS" "$NC"

# --- STEP 1.7: AUTH KEY INPUT ---
if [[ -f "$TS_AUTHKEY_FILE" ]]; then
  DEFAULT_AUTH_KEY="$(<"$TS_AUTHKEY_FILE")"
  DEFAULT_AUTH_KEY="${DEFAULT_AUTH_KEY//$'\n'/}"
else
  DEFAULT_AUTH_KEY=""
fi
printf "Auth key (%s%s%s): " "$BOLD" "$DEFAULT_AUTH_KEY" "$NC"
read -r INPUT_KEY
[[ "$INPUT_KEY" == "q" ]] && exit 0
AUTH_KEY="${INPUT_KEY:-$DEFAULT_AUTH_KEY}"
printf "\nUsing auth key: %s\n\n" "$AUTH_KEY"

# --- STEP 1.8: BASE PATH INPUT ---
printf "Base path (%s%s%s): " "$BOLD" "$DEFAULT_BASE_PATH" "$NC"
read -r INPUT_BASE
[[ "$INPUT_BASE" == "q" ]] && exit 0
BASE_PATH="${INPUT_BASE:-$DEFAULT_BASE_PATH}"
printf "\nUsing base path: %s\n\n" "$BASE_PATH"

# --- STEP 2: ENVIRONMENT VARIABLES ---
ENV_JSON=$(jq -c --arg name "$SELECTED_RAW_NAME" \
  '.[] | select(.name == $name).environment' "$JSON_FILE")
declare -A ENV_VARS
while IFS=" " read -r k v; do
  ENV_VARS["$k"]="$v"
done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$ENV_JSON")

for key in "${!ENV_VARS[@]}"; do
  default="${ENV_VARS[$key]}"
  printf "Enter %s (%s%s%s): " "$key" "$BOLD" "$default" "$NC"
  read -r val
  [[ "$val" == "q" ]] && exit 0
  ENV_VARS["$key"]="${val:-$default}"
  printf "\n"
done
env_keys=("${!ENV_VARS[@]}")

# --- STEP 3: VOLUME MAPPINGS ---
mapfile -t CONTAINER_PATHS < <(jq -r --arg name "$SELECTED_RAW_NAME" \
  '.[] | select(.name == $name).volumes | to_entries[].value' "$JSON_FILE")
declare -A VOLUMES
for cp in "${CONTAINER_PATHS[@]}"; do
  sub="${cp#/}"
  default_host="$BASE_PATH/$SELECTED_RAW_NAME/$sub"
  printf "Host path for %s (%s%s%s): " "$cp" "$BOLD" "$default_host" "$NC"
  read -r h
  [[ "$h" == "q" ]] && exit 0
  VOLUMES["$cp"]="${h:-$default_host}"
  printf "\n"
done

printf "Would you like to add more volumes? [%sno%s/%syes%s]: " "$BOLD" "$NC" "$BOLD" "$NC"
read -r MORE
[[ "$MORE" == "q" ]] && exit 0
MORE="${MORE:-no}"
printf "\n"
if [[ "$MORE" == "yes" ]]; then
  while true; do
    printf "Enter additional container path: "
    read -r cp; [[ "$cp" == "q" ]] && exit 0
    printf "Enter host path for %s: " "$cp"
    read -r hp; [[ "$hp" == "q" ]] && exit 0
    VOLUMES["$cp"]="$hp"
    printf "\n"
    printf "More volumes? [%sno%s/%syes%s]: " "$BOLD" "$NC" "$BOLD" "$NC"
    read -r MORE; [[ "$MORE" == "q" ]] && exit 0
    MORE="${MORE:-no}"
    printf "\n"
    [[ "$MORE" != "yes" ]] && break
  done
fi
vol_keys=("${!VOLUMES[@]}")

# --- FINAL JSON + CONFIRMATION ---
SPEC=$(jq -c --arg name "$SELECTED_RAW_NAME" \
  '.[] | select(.name == $name)' "$JSON_FILE")
IMAGE=$(jq -r '.image' <<<"$SPEC")
PORTS=$(jq '.ports' <<<"$SPEC")
RESTART=$(jq -r '.restart_policy' <<<"$SPEC")
DEF_NET=$(jq -r '.network_mode' <<<"$SPEC")
if [[ "$INCLUDE_TS" == "yes" ]]; then
  NETWORK="service:tailscale-$SELECTED_RAW_NAME"
else
  NETWORK="$DEF_NET"
fi

TMP_JSON="$(mktemp)"
{
  printf '{\n'
  printf '  "container": "%s",\n' "$SELECTED_RAW_NAME"
  printf '  "image": "%s",\n' "$IMAGE"
  printf '  "network_mode": "%s",\n' "$NETWORK"
  printf '  "ports": %s,\n' "$PORTS"
  printf '  "restart_policy": "%s",\n' "$RESTART"
  printf '  "include_npm": "%s",\n' "$INCLUDE_NPM"
  printf '  "include_tailscale": "%s",\n' "$INCLUDE_TS"
  printf '  "auth_key": "%s",\n' "$AUTH_KEY"
  printf '  "base_path": "%s",\n' "$BASE_PATH"
  printf '  "environment": {\n'
  for i in "${!env_keys[@]}"; do
    k="${env_keys[i]}"; v="${ENV_VARS[$k]}"
    comma=$([[ $i -lt $(( ${#env_keys[@]} - 1 )) ]] && echo "," || echo "")
    printf '    "%s": "%s"%s\n' "$k" "$v" "$comma"
  done
  printf '  },\n'
  printf '  "volumes": {\n'
  for i in "${!vol_keys[@]}"; do
    k="${vol_keys[i]}"; v="${VOLUMES[$k]}"
    comma=$([[ $i -lt $(( ${#vol_keys[@]} - 1 )) ]] && echo "," || echo "")
    printf '    "%s": "%s"%s\n' "$k" "$v" "$comma"
  done
  printf '  }\n'
  printf '}\n'
} | tee "$TMP_JSON"

printf "\nThe following will be used to create a pod:\n\n"
cat "$TMP_JSON"
printf "\n"

# Confirmation loop
while true; do
  printf "Would you like to continue? (yes/no): "
  read -r CONT
  if [[ "$CONT" == "q" ]]; then
    rm "$TMP_JSON"
    exit 0
  elif [[ "$CONT" == "yes" ]]; then
    break
  elif [[ "$CONT" == "no" ]]; then
    printf "Aborted.\n"
    rm "$TMP_JSON"
    exit 0
  else
    printf "Please answer yes or no.\n\n"
  fi
done

# Pipe JSON into create.sh
bash "$SCRIPT_DIR/create.sh" < "$TMP_JSON"
rm "$TMP_JSON"

# Call cleanup script if it exists
if [[ -f "$SCRIPT_DIR/cleanup.sh" ]]; then
    echo ""
    echo "Running cleanup..."
    bash "$SCRIPT_DIR/cleanup.sh"
fi
