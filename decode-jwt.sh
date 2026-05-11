#!/bin/bash

# --- Color Definitions ---
BLUE='\033[1;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Help Function ---
show_help() {
  echo -e "\n${BLUE}${BOLD}JWT DECODER HELP${NC}"
  draw_line
  echo -e "${YELLOW}Usage:${NC} $0 <jwt-or-payload> [timezone]"
  echo -e "       $0 --diff <jwt1> <jwt2> [timezone]"
  echo -e "\n${BOLD}Options:${NC}"
  printf "  %-15s %s\n" "-h, --help" "Show this help message"
  printf "  %-15s %s\n" "-l, --list-tz" "Show common timezone values"
  printf "  %-15s %s\n" "-c, --diff" "Compare two different JWT tokens"
  echo -e "\n${BOLD}Example:${NC}"
  echo -e "  $0 --diff <token1> <token2> UTC"
  draw_line
  echo ""
  exit 0
}

# --- Timezone Listing Function ---
list_timezones() {
  echo -e "\n${BLUE}${BOLD}COMMON TIMEZONE VALUES${NC}"
  echo -e "${CYAN}------------------------------------------------------------${NC}"
  printf "${YELLOW}%-20s${NC} | ${YELLOW}%s${NC}\n" "Region" "Example String"
  echo -e "------------------------------------------------------------"
  printf "%-20s | %s\n" "Universal" "UTC, GMT"
  printf "%-20s | %s\n" "US (East/West)" "America/New_York, America/Los_Angeles"
  printf "%-20s | %s\n" "Europe" "Europe/London, Europe/Paris"
  printf "%-20s | %s\n" "Asia" "Asia/Colombo, Asia/Tokyo"
  echo -e "${CYAN}------------------------------------------------------------${NC}"
  echo -e "${BOLD}Tip:${NC} Use underscores for spaces (e.g., New_York)."
  
  if command -v timedatectl >/dev/null 2>&1; then
    echo -e "\nTo see all zones on this system, run: ${GREEN}timedatectl list-timezones${NC}"
  else
    echo -e "\nTo see all zones on your Mac, run: ${GREEN}find /usr/share/zoneinfo -type f | cut -d/ -f5- | sort${NC}"
  fi
  echo ""
  exit 0
}

# --- Argument Check ---
if [ $# -lt 1 ]; then
  echo -e "${RED}Usage:${NC} $0 <jwt-or-payload> [timezone]"
  echo -e "       $0 -h for help"
  exit 1
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
fi

if [[ "$1" == "--list-tz" || "$1" == "-l" ]]; then
  list_timezones
fi

# --- Helper Functions ---
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

clean_input() {
    echo "$1" | sed -E 's/^(jwt|JWT)[[:space:]]+//' | tr -d '[:space:]'
}

# --- Core Processing ---
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
    
    # Shows current time in the active timezone
    printf "${CYAN}%-15s${NC} : %s\n" "Current Clock" "$(date -r "$now" "+%B %d, %Y at %I:%M:%S %p %Z")"

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

  echo "$raw_json" | jq "$JQ_TIME_FILTER" 2>/dev/null || echo -e "${RED}Error parsing JSON${NC}"
  echo ""
}

# --- Main Logic ---
run_decode() {
    local input_str="$1"
    local num_parts=$(awk -F'.' '{print NF}' <<< "$input_str")
    if (( num_parts == 3 )); then
      process_segment "HEADER" "$(decode_base64url "$(echo "$input_str" | cut -d. -f1)")" "false"
      process_segment "PAYLOAD" "$(decode_base64url "$(echo "$input_str" | cut -d. -f2)")" "true"
    elif (( num_parts == 2 )); then
      p1_decoded=$(decode_base64url "$(echo "$input_str" | cut -d. -f1)")
      if echo "$p1_decoded" | jq -e 'has("iat") or has("exp") or has("sub")' >/dev/null 2>&1; then
        process_segment "PAYLOAD (Part 1)" "$p1_decoded" "true"
        # RESTORED: Show signature when part 1 is the payload
        echo -e "${BLUE}${BOLD}SIGNATURE (Part 2)${NC}\n$(echo "$input_str" | cut -d. -f2)"
      else
        process_segment "HEADER (Part 1)" "$p1_decoded" "false"
        process_segment "PAYLOAD (Part 2)" "$(decode_base64url "$(echo "$input_str" | cut -d. -f2)")" "true"
      fi
    else
      process_segment "PAYLOAD" "$(decode_base64url "$input_str")" "true"
    fi
}

# --- Comparison Mode Logic ---
if [[ "$1" == "--diff" || "$1" == "-c" ]]; then
    if [ $# -lt 3 ]; then echo -e "${RED}Error: Two tokens required for comparison.${NC}"; exit 1; fi
    
    if [ -n "$4" ]; then export TZ="$4"; fi
    
    token1=$(clean_input "$2")
    token2=$(clean_input "$3")
    
    echo -e "\n${YELLOW}${BOLD}COMPARING TWO TOKENS${NC} (TZ: $(date +%Z))\n"
    
    # Create temp files and setup trap for cleanup
    file1=$(mktemp)
    file2=$(mktemp)
    trap 'rm -f "$file1" "$file2" 2>/dev/null' EXIT
    
    # Refactored smart payload extraction for diffing
    get_payload() {
        local t=$(clean_input "$1")
        local num=$(awk -F'.' '{print NF}' <<< "$t")
        if (( num == 3 )); then 
            decode_base64url "$(echo "$t" | cut -d. -f2)"
        elif (( num == 2 )); then 
            local p1=$(decode_base64url "$(echo "$t" | cut -d. -f1)")
            # Fix: Use same smart check as run_decode
            if echo "$p1" | jq -e 'has("iat") or has("exp") or has("sub")' >/dev/null 2>&1; then
                echo "$p1"
            else
                decode_base64url "$(echo "$t" | cut -d. -f2)"
            fi
        else 
            decode_base64url "$t"
        fi
    }

    get_payload "$token1" | jq -S "$JQ_TIME_FILTER" > "$file1"
    get_payload "$token2" | jq -S "$JQ_TIME_FILTER" > "$file2"

    echo -e "${BLUE}Legend: ${RED}- Token 1${NC} | ${GREEN}+ Token 2${NC}\n"
    diff --color=always -u "$file1" "$file2" | sed '1,2d'
    
    draw_line
    exit 0
fi

# --- Standard Single Token Logic ---
if [ -n "$2" ]; then
  export TZ="$2"
fi
DISPLAY_TZ=$(date +%Z)
input=$(clean_input "$1")

echo -e "\n${YELLOW}Active Timezone: ${BOLD}$DISPLAY_TZ${NC}"
if [ -z "$2" ]; then echo -e "${CYAN}(Detected from local computer)${NC}"; fi
echo ""

run_decode "$input"

draw_line
echo ""
