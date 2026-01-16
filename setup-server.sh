#!/bin/bash
# Quick setup script for DIY Dynamic DNS Server

set -e

echo "==================================="
echo "DIY Dynamic DNS - Server Setup"
echo "==================================="
echo

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Get port
read -p "Enter port to listen on [8080]: " PORT
PORT=${PORT:-8080}

# Get IP file path
read -p "Enter path for IP file [/var/www/html/myip.txt]: " IP_FILE
IP_FILE=${IP_FILE:-/var/www/html/myip.txt}

# Create directory
echo "Creating directory for IP file..."
mkdir -p "$(dirname "$IP_FILE")"

# Create initial IP file
touch "$IP_FILE"
echo "0.0.0.0" > "$IP_FILE"

echo
echo "Configuration:"
echo "  Port: $PORT"
echo "  IP file: $IP_FILE"
echo

echo "Starting server..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "Server will be accessible at:"
echo "  http://localhost:$PORT/ip"
echo "  http://<your-server-ip>:$PORT/ip"
echo
echo "Press Ctrl+C to stop"
echo

python3 "$SCRIPT_DIR/server.py" --port "$PORT" --ip-file "$IP_FILE"
