# jwt-decoder

A terminal-focused Bash script to decode, format, and compare JSON Web Tokens (JWTs). It automatically translates UNIX epoch timestamps into human-readable dates using your local or preferred timezone, calculates token expiration lifespans, and provides a direct terminal diff tool for structural debugging.

## How it Works

1. The script validates input structures and automatically adjusts missing base64url padding to decode token segments into raw JSON.
2. It parses the payload via `jq`, recursively sweeping for standard timestamp claims (`exp`, `iat`, `nbf`) to translate them into localized date-time strings.
3. It evaluates the current clock against expiration metrics to display real-time status indicators (active, expired, remaining time, and total lifespan).
4. For comparisons, it isolates and alpha-sorts key fields from two independent payloads to pipe a colorized, unified diff straight to the stdout.

## Prerequisites

This script requires `jq` for JSON manipulation and timestamp formatting.

```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq

```

## Usage

```bash
# Make executable
chmod +x jwt-decode.sh

# Decode a single token (autodetects timezone)
./jwt-decode.sh <jwt-token> [timezone]

# Compare two tokens
./jwt-decode.sh --diff <token1> <token2> [timezone]

# List common timezones
./jwt-decode.sh --list-tz

```

## Examples

### Standard Decode

```bash
./jwt-decode.sh eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE1MTYyNDI2MjJ9.signature

```

**Output:**

```text
Active Timezone: EST
(Detected from local computer)

HEADER
------------------------------------------------------------
{
  "alg": "HS256",
  "typ": "JWT"
}

PAYLOAD
------------------------------------------------------------
TOKEN METADATA
Current Clock   : May 18, 2026 at 11:37:50 AM EST
Status          : EXPIRED (272314 min ago)
Total Lifespan  : 1h 0m 0s
------------------------------------------------------------
{
  "sub": "1234567890",
  "name": "John Doe",
  "iat": "January 18, 2018 at 03:17:02 PM EST",
  "exp": "January 18, 2018 at 04:17:02 PM EST"
}

```

### Comparing Tokens

```bash
./jwt-decode.sh --diff <token_1> <token_2> UTC

```

**Output:**

```text
COMPARING TWO TOKENS (TZ: UTC)

Legend: - Token 1 | + Token 2

@@ -1,6 +1,6 @@
 {
-  "exp": "May 18, 2026 at 12:00:00 PM UTC",
-  "role": "user",
+  "exp": "May 18, 2026 at 01:00:00 PM UTC",
+  "role": "admin",
   "sub": "1234567890"
 }
------------------------------------------------------------

```
