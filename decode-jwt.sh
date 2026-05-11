#!/bin/bash

# --- Color Definitions ---
BLUE='\033[1;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

if [ $# -lt 1 ]; then
  echo -e "${RED}Usage:${NC} $0 <jwt-or-payload> [timezone]"
  exit 1
fi

input="$1"
user_tz="${2:-$(date +%Z)}"

# Updated JQ Filter: Format = "May 11, 2026 at 12:01 PM PST"
JQ_TIME_FILTER='walk(
  if type == "object" then
    with_entries(
      if (.key | test("exp|iat|nbf|auth_time|_at$")) and (.value | type == "number") then
        .value |= ( . | strflocaltime("%B %e, %Y at %I:%M:%S %p %Z") )
      else
        .
      end
    )
  else
    .
  end
)'

decode_base64url() {
  segment="$1"
  segment=$(echo "$segment" | tr '_-' '/+')
  padding=$(( (4 - ${#segment} % 4) % 4 ))
  for ((i=0; i<padding; i++)); do segment="${segment}="; done
  echo "$segment" | base64 -D 2>/dev/null || echo "$segment" | base64 -d 2>/dev/null
}

draw_line() {
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

process_payload() {
  local raw_json="$1"
  local now=$(date +%s)
  
  local iat=$(echo "$raw_json" | jq -r '.iat // empty' 2>/dev/null)
  local exp=$(echo "$raw_json" | jq -r '.exp // empty' 2>/dev/null)

  draw_line
  echo -e "${BLUE}${BOLD}TOKEN METADATA${NC}"
  
  # Current Clock in target TZ
  printf "${CYAN}%-15s${NC} : %s\n" "Current Clock" "$(TZ="$user_tz" date -r "$now" "+%B %d, %Y at %I:%M:%S %p %Z")"

  if [[ -n "$exp" && "$exp" =~ ^[0-9]+$ ]]; then
    if [ "$now" -gt "$exp" ]; then
      local diff=$((now - exp))
      printf "${CYAN}%-15s${NC} : ${RED}EXPIRED${NC} (${BOLD}$((diff / 60)) min ago${NC})\n" "Status"
    else
      local diff=$((exp - now))
      printf "${CYAN}%-15s${NC} : ${GREEN}ACTIVE${NC} (Expires in ${BOLD}$((diff / 3600))h $(((diff % 3600) / 60))m${NC})\n" "Status"
    fi
  fi

  if [[ -n "$iat" && -n "$exp" ]]; then
    local lifespan=$((exp - iat))
    printf "${CYAN}%-15s${NC} : %dh %dm %ds\n" "Total Lifespan" "$((lifespan / 3600))" "$(((lifespan % 3600) / 60))" "$((lifespan % 60))"
  fi
  draw_line

  echo -e "${BLUE}${BOLD}PAYLOAD DATA${NC}"
  echo "$raw_json" | TZ="$user_tz" jq "$JQ_TIME_FILTER" 2>/dev/null || echo -e "${RED}Error parsing JSON payload${NC}"
}

# --- Main Logic ---
num_parts=$(awk -F'.' '{print NF}' <<< "$input")

echo -e "\n${YELLOW}Decoding JWT for Timezone: ${BOLD}$user_tz${NC}\n"

if (( num_parts >= 2 )); then
  header_enc=$(echo "$input" | cut -d. -f1)
  payload_enc=$(echo "$input" | cut -d. -f2)
  
  echo -e "${BLUE}${BOLD}HEADER${NC}"
  decode_base64url "$header_enc" | TZ="$user_tz" jq "$JQ_TIME_FILTER" 2>/dev/null || decode_base64url "$header_enc"
  echo
  
  process_payload "$(decode_base64url "$payload_enc")"
else
  process_payload "$(decode_base64url "$input")"
fi

draw_line
echo ""
