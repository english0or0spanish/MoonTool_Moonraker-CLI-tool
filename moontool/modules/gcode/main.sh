#!/usr/bin/env bash

# gcode/main.sh - Send G-code commands

if [[ "$1" == --* ]]; then
    HOST="${1#--}"
    shift
else
    echo "Usage: moontool.sh gcode --<ip:port> <gcode_command>"
    exit 1
fi

if [ -z "$*" ]; then
    echo "Error: No G-code command provided"
    exit 1
fi

# URL encode function
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

GCODE="$*"
ENCODED=$(urlencode "$GCODE")

# Temp file for tracking
TMPFILE=$(mktemp)
SEEN_FILE=$(mktemp)

# Send command in background
curl -s -X POST "http://${HOST}/printer/gcode/script?script=${ENCODED}" -H "Content-Length: 0" > "$TMPFILE" &
CURL_PID=$!

# Poll gcode_store until POST completes
while kill -0 $CURL_PID 2>/dev/null; do
    # Get gcode store
    RESPONSE=$(curl -s "http://${HOST}/server/gcode_store?count=100")
    
    # Extract all messages line by line
    echo "$RESPONSE" | sed -n 's/.*"message":[[:space:]]*"\([^"]*\)".*/\1/p' | while read -r line; do
        # Skip if it's the command itself
        if [ "$line" = "$GCODE" ]; then
            continue
        fi
        
        # Skip if we've seen this message
        if grep -Fxq "$line" "$SEEN_FILE" 2>/dev/null; then
            continue
        fi
        
        # New message - show it and remember it
        echo "$line"
        echo "$line" >> "$SEEN_FILE"
    done
    
    sleep 0.1
done

# Final check for any remaining messages
RESPONSE=$(curl -s "http://${HOST}/server/gcode_store?count=100")
echo "$RESPONSE" | sed -n 's/.*"message":[[:space:]]*"\([^"]*\)".*/\1/p' | while read -r line; do
    if [ "$line" = "$GCODE" ]; then
        continue
    fi
    if grep -Fxq "$line" "$SEEN_FILE" 2>/dev/null; then
        continue
    fi
    echo "$line"
done

# Cleanup
rm -f "$TMPFILE" "$SEEN_FILE"
