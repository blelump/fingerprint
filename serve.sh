#!/usr/bin/env bash
# serve.sh — serve this directory over HTTP (or HTTPS with --tls)
#
# Usage:
#   ./serve.sh            # http on port 8000
#   ./serve.sh 3000       # http on port 3000
#   ./serve.sh --tls      # https on port 8443 (self-signed cert)
#   ./serve.sh 3000 --tls # https on port 3000
#
# Why --tls? Browsers only allow "secure context" APIs (crypto.subtle,
# mediaDevices, clipboard, geolocation) on https:// OR http://localhost.
# If you open the page via a LAN IP (e.g. from a phone), you need --tls.

set -euo pipefail

PORT=""
TLS=0
for arg in "$@"; do
  case "$arg" in
    --tls) TLS=1 ;;
    *) PORT="$arg" ;;
  esac
done
[ -z "$PORT" ] && PORT=$((TLS ? 8443 : 8000))
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# --- pick a server runtime ---
PY=""
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
fi

# --- TLS mode ---
if [ "$TLS" = 1 ]; then
  CERT_DIR="$DIR/.cert"
  CERT="$CERT_DIR/cert.pem"
  KEY="$CERT_DIR/key.pem"
  if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: --tls requires openssl (to make a self-signed cert)." >&2
    exit 1
  fi
  [ -f "$CERT" ] || { mkdir -p "$CERT_DIR"; openssl req -x509 -newkey rsa:2048 \
      -keyout "$KEY" -out "$CERT" -days 30 -nodes \
      -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
      >/dev/null 2>&1; }
  echo "Serving $DIR on https://localhost:$PORT  (self-signed — click through the browser warning: 'Advanced' → 'Proceed')"
  exec "$PY" - "$PORT" "$CERT" "$KEY" <<'PYEOF'
import http.server, ssl, sys
port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
httpd = http.server.HTTPServer(("0.0.0.0", port), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
print(f"listening on https://0.0.0.0:{port} ... Ctrl+C to stop")
httpd.serve_forever()
PYEOF
fi

# --- plain HTTP mode ---
echo "Serving $DIR on http://localhost:$PORT"
echo "Open:  http://localhost:$PORT/index.html"
echo "NOTE: if you open via a LAN IP instead of localhost, use --tls or secure-context APIs will be blocked."
echo "Ctrl+C to stop."

if [ -n "$PY" ]; then
  exec "$PY" -m http.server "$PORT" --bind 0.0.0.0
elif command -v busybox >/dev/null 2>&1; then
  exec busybox httpd -f -p "$PORT" -h "$DIR"
elif command -v php >/dev/null 2>&1; then
  exec php -S "0.0.0.0:$PORT"
else
  echo "Error: no python3/python/busybox/php found to serve with." >&2
  exit 1
fi
