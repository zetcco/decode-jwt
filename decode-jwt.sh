#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <jwt-or-payload>"
  echo "Provide a JWT with 1 to 3 parts separated by dots (a.b.c), (a.b), or just payload (b)."
  exit 1
fi

input="$1"

# This jq filter finds keys that look like timestamps and converts them
# It targets: exp, iat, nbf, auth_time, and any key ending in _at
JQ_FILTER='walk(
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
  # Convert base64url to base64
  segment=$(echo "$segment" | tr '_-' '/+')
  # Add padding if needed
  padding=$(( (4 - ${#segment} % 4) % 4 ))
  for ((i=0; i<padding; i++)); do
    segment="${segment}="
  done
  # Note: Use -d instead of -D if on Linux
  echo "$segment" | base64 -D 2>/dev/null || echo "$segment" | base64 -d 2>/dev/null
}

# Count the number of sections split by '.'
num_parts=$(awk -F'.' '{print NF}' <<< "$input")

if (( num_parts == 3 )); then
  header=$(echo "$input" | cut -d. -f1)
  payload=$(echo "$input" | cut -d. -f2)

  echo "### Header ###"
  decode_base64url "$header" | jq "$JQ_FILTER" 2>/dev/null || decode_base64url "$header"
  echo

  echo "### Payload ###"
  decode_base64url "$payload" | jq "$JQ_FILTER" 2>/dev/null || decode_base64url "$payload"

elif (( num_parts == 2 )); then
  header=$(echo "$input" | cut -d. -f1)
  payload=$(echo "$input" | cut -d. -f2)

  echo "### Header ###"
  decode_base64url "$header" | jq "$JQ_FILTER" 2>/dev/null || decode_base64url "$header"
  echo

  echo "### Payload ###"
  decode_base64url "$payload" | jq "$JQ_FILTER" 2>/dev/null || decode_base64url "$payload"

elif (( num_parts == 1 )); then
  echo "### Payload ###"
  decode_base64url "$input" | jq "$JQ_FILTER" 2>/dev/null || decode_base64url "$input"

else
  echo "Invalid input: Unexpected number of JWT parts ($num_parts)"
  exit 1
fi

