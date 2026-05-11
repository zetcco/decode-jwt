#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <jwt-or-payload>"
  echo "Provide a JWT with 1 to 3 parts separated by dots (a.b.c), (a.b), or just payload (b)."
  exit 1
fi

input="$1"

# JQ Filter to convert timestamps to local human-readable time
JQ_TIME_FILTER='walk(
  if type == "object" then
    with_entries(
      if (.key | test("exp|iat|nbf|auth_time|_at$")) and (.value | type == "number") then
        .value |= ( . | strflocaltime("%Y-%m-%d %H:%M:%S %Z") )
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
  for ((i=0; i<padding; i++)); do
    segment="${segment}="
  done
  # Attempt macOS format (-D), fallback to Linux/GNU format (-d)
  echo "$segment" | base64 -D 2>/dev/null || echo "$segment" | base64 -d 2>/dev/null
}

process_payload() {
  local raw_json="$1"
  
  # 1. Show the lifespan if exp and iat are present
  local iat=$(echo "$raw_json" | jq -r '.iat // empty' 2>/dev/null)
  local exp=$(echo "$raw_json" | jq -r '.exp // empty' 2>/dev/null)

  if [[ -n "$iat" && -n "$exp" && "$iat" =~ ^[0-9]+$ && "$exp" =~ ^[0-9]+$ ]]; then
    local diff=$((exp - iat))
    local h=$((diff / 3600))
    local m=$(( (diff % 3600) / 60 ))
    local s=$((diff % 60))
    echo "--- Token Metadata ---"
    printf "Total Lifespan: %dh %dm %ds (%d total seconds)\n" "$h" "$m" "$s" "$diff"
    echo "----------------------"
  fi

  # 2. Show the prettified JSON with local times
  echo "Payload:"
  echo "$raw_json" | jq "$JQ_TIME_FILTER" 2>/dev/null || echo "$raw_json"
}

# Count the number of sections split by '.'
num_parts=$(awk -F'.' '{print NF}' <<< "$input")

if (( num_parts == 3 || num_parts == 2 )); then
  header_enc=$(echo "$input" | cut -d. -f1)
  payload_enc=$(echo "$input" | cut -d. -f2)

  echo "### Header ###"
  decode_base64url "$header_enc" | jq "$JQ_TIME_FILTER" 2>/dev/null || decode_base64url "$header_enc"
  echo

  echo "### Payload ###"
  process_payload "$(decode_base64url "$payload_enc")"

elif (( num_parts == 1 )); then
  echo "### Payload ###"
  process_payload "$(decode_base64url "$input")"

else
  echo "Invalid input: Unexpected number of JWT parts ($num_parts)"
  exit 1
fi
