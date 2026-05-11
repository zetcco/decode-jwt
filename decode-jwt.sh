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

# 1. CLEAN INPUT: Strip "jwt " prefix (case insensitive) and remove whitespace
input=$(echo "$1" | sed -E 's/^(jwt|JWT)[[:space:]]+//' | tr -d '[:space:]')
user_tz="${2:-$(date +%Z)}"

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
  local segment="$1"
  segment=$(echo "$segment" | tr '_-' '/+')
  local padding=$(( (4 - ${#segment} % 4) % 4 ))
  for ((i=0; i<padding; i++)); do segment="${segment}="; done
  echo "$segment" | base64 -D 2>/dev/null || echo "$segment" | base64 -d 2>/dev/null
}

draw_line() {
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

# Displays Metadata and the JSON body
process_segment() {
  local label="$1"
  local raw_json="$2"
  local is_payload="$3"
  local now=$(date +%s)
  
  echo -e "${BLUE}${BOLD}$label${NC}"

  if [[ "$is_payload" == "true" ]]; then
    local iat=$(echo "$raw_json" | jq -r '.iat // empty' 2>/dev/null)
    local exp=$(echo "$raw_json" | jq -r '.exp // empty' 2>/dev/null)

    draw_line
    echo -e "${YELLOW}${BOLD}TOKEN METADATA${NC}"
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
  fi

  echo "$raw_json" | TZ="$user_tz" jq "$JQ_TIME_FILTER" 2>/dev/null || echo -e "${RED}Error parsing JSON${NC}"
  echo ""
}

# --- Main Logic ---
num_parts=$(awk -F'.' '{print NF}' <<< "$input")

echo -e "\n${YELLOW}Decoding for Timezone: ${BOLD}$user_tz${NC}\n"

if (( num_parts == 3 )); then
  # Standard JWT: Header.Payload.Signature
  process_segment "HEADER" "$(decode_base64url "$(echo "$input" | cut -d. -f1)")" "false"
  process_segment "PAYLOAD" "$(decode_base64url "$(echo "$input" | cut -d. -f2)")" "true"

elif (( num_parts == 2 )); then
  # Two parts: Could be Header.Payload OR Payload.Signature
  p1_decoded=$(decode_base64url "$(echo "$input" | cut -d. -f1)")
  
  # Smart Check: Does Part 1 look like a payload?
  if echo "$p1_decoded" | jq -e 'has("iat") or has("exp") or has("sub")' >/dev/null 2>&1; then
    process_segment "PAYLOAD (Part 1)" "$p1_decoded" "true"
    echo -e "${BLUE}${BOLD}SIGNATURE (Part 2)${NC}\n$(echo "$input" | cut -d. -f2)"
  else
    process_segment "HEADER (Part 1)" "$p1_decoded" "false"
    process_segment "PAYLOAD (Part 2)" "$(decode_base64url "$(echo "$input" | cut -d. -f2)")" "true"
  fi

else
  # Single part
  process_segment "PAYLOAD" "$(decode_base64url "$input")" "true"
fi

draw_line
echo ""
