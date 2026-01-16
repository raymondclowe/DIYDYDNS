#!/bin/bash
# Quick setup script for DIY Dynamic DNS Client

set -e

echo "==================================="
echo "DIY Dynamic DNS - Client Setup"
echo "==================================="
echo

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed"
    exit 1
fi

# Get server details
read -p "Enter your server address (user@server.com): " SERVER
if [ -z "$SERVER" ]; then
    echo "Error: Server address is required"
    exit 1
fi

# Test SSH connection
echo "Testing SSH connection to $SERVER..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" "echo 'SSH connection successful'" 2>/dev/null; then
    echo "✓ SSH connection successful"
else
    echo "✗ SSH connection failed"
    echo
    echo "Please ensure:"
    echo "1. SSH server is running on the remote host"
    echo "2. You have SSH key authentication set up"
    echo "   Run: ssh-copy-id $SERVER"
    exit 1
fi

# Get remote path
read -p "Enter remote path for IP file [/var/www/html/myip.txt]: " REMOTE_PATH
REMOTE_PATH=${REMOTE_PATH:-/var/www/html/myip.txt}

# Test write permissions
echo "Testing write permissions on remote server..."
if ssh "$SERVER" "mkdir -p \"\$(dirname \"$REMOTE_PATH\")\" && touch \"$REMOTE_PATH\"" 2>/dev/null; then
    echo "✓ Write permissions OK"
else
    echo "✗ Cannot write to $REMOTE_PATH on remote server"
    echo "  Please ensure the path is writable by your user"
    exit 1
fi

# Get interval
read -p "Enter check interval in seconds [300]: " INTERVAL
INTERVAL=${INTERVAL:-300}

echo
echo "Configuration:"
echo "  Server: $SERVER"
echo "  Remote path: $REMOTE_PATH"
echo "  Interval: $INTERVAL seconds"
echo

# Run test
echo "Running test update..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if python3 "$SCRIPT_DIR/client.py" --server "$SERVER" --remote-path "$REMOTE_PATH" --once; then
    echo "✓ Test successful!"
else
    echo "✗ Test failed"
    exit 1
fi

echo
echo "Setup complete!"
echo
echo "To start monitoring continuously, run:"
echo "  python3 $SCRIPT_DIR/client.py --server $SERVER --remote-path $REMOTE_PATH --interval $INTERVAL"
echo
echo "Or install as a systemd service for automatic startup."
