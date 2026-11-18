#!/bin/sh
cd "$(dirname "$0")" || exit 1
URL="http://localhost:8642"

# The app needs Node.js for its small local server (Web Serial and WebHID only work on localhost/https).
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js was not found. Install it from https://nodejs.org and run this again."
  exit 1
fi

# Start the server unless it is already running.
if ! lsof -nP -iTCP@127.0.0.1:8642 -sTCP:LISTEN >/dev/null 2>&1 && ! nc -z 127.0.0.1 8642 >/dev/null 2>&1; then
  node serve.js >/dev/null 2>&1 &
  sleep 1
fi

# Open as an app window in Chrome or Edge (Web Serial and WebHID need a Chromium browser).
BROWSER=""
for B in \
  "/Applications/Google Chrome.app" \
  "$HOME/Applications/Google Chrome.app" \
  "/Applications/Microsoft Edge.app" \
  "$HOME/Applications/Microsoft Edge.app"
do
  if [ -z "$BROWSER" ] && [ -d "$B" ]; then
    BROWSER="$B"
  fi
done

if [ -n "$BROWSER" ]; then
  open -na "$BROWSER" --args --app="$URL"
else
  echo "Chrome or Edge not found, opening the default browser. Web Serial and WebHID need Chrome or Edge."
  open "$URL"
fi
