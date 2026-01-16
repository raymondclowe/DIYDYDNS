#!/bin/bash
# Integration test for DIY Dynamic DNS

set -e

echo "======================================"
echo "DIY Dynamic DNS - Integration Test"
echo "======================================"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/tmp/diydydns_test_$$"
TEST_IP="203.0.113.42"

# Function to find an available port
find_available_port() {
    local port
    for i in {1..10}; do
        port=$((10000 + RANDOM % 10000))
        if ! netstat -tln 2>/dev/null | grep -q ":$port " && ! ss -tln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    # Fallback to random port if checks unavailable
    echo $((10000 + RANDOM % 10000))
}

TEST_PORT=$(find_available_port)

# Cleanup function
cleanup() {
    echo
    echo "Cleaning up..."
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# Create test directory
mkdir -p "$TEST_DIR"

echo "Test 1: Server starts and serves IP"
echo "-----------------------------------"

# Create test IP file
echo "$TEST_IP" > "$TEST_DIR/myip.txt"

# Start server in background
python3 "$SCRIPT_DIR/server.py" --port "$TEST_PORT" --ip-file "$TEST_DIR/myip.txt" &
SERVER_PID=$!

# Wait for server to start
sleep 2

# Test /ip endpoint
RESPONSE=$(curl -s http://localhost:$TEST_PORT/ip)
if [ "$RESPONSE" = "$TEST_IP" ]; then
    echo "✓ Server correctly serves IP: $RESPONSE"
else
    echo "✗ Server returned unexpected IP: $RESPONSE (expected: $TEST_IP)"
    exit 1
fi

# Test /health endpoint
RESPONSE=$(curl -s http://localhost:$TEST_PORT/health)
if [ "$RESPONSE" = "OK" ]; then
    echo "✓ Health check endpoint works"
else
    echo "✗ Health check returned: $RESPONSE"
    exit 1
fi

echo
echo "Test 2: Client functions (without SCP)"
echo "---------------------------------------"

# Test IP detection function (may fail in restricted environments)
echo "Testing IP detection (may fail if external services are blocked)..."
python3 -c "
from client import get_public_ip
ip = get_public_ip()
if ip:
    print(f'✓ IP detection works: {ip}')
else:
    print('⚠ IP detection failed (expected in restricted environments)')
" || echo "⚠ IP detection unavailable"

# Test cache functions
echo "Testing cache read/write..."
python3 -c "
from client import read_cached_ip, write_cached_ip
import os

cache_file = '$TEST_DIR/test_cache.txt'
test_ip = '192.0.2.1'

# Write test
if write_cached_ip(cache_file, test_ip):
    print('✓ Cache write successful')
else:
    print('✗ Cache write failed')
    exit(1)

# Read test
cached = read_cached_ip(cache_file)
if cached == test_ip:
    print(f'✓ Cache read successful: {cached}')
else:
    print(f'✗ Cache read failed: {cached}')
    exit(1)
"

echo
echo "Test 3: Server handles missing IP file"
echo "---------------------------------------"

# Stop existing server
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
sleep 2

# Remove IP file
rm -f "$TEST_DIR/myip.txt"

# Start server again
TEST_PORT2=$(find_available_port)
python3 "$SCRIPT_DIR/server.py" --port "$TEST_PORT2" --ip-file "$TEST_DIR/myip.txt" &
SERVER_PID=$!
sleep 2

# Should return 503
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$TEST_PORT2/ip)
if [ "$HTTP_CODE" = "503" ]; then
    echo "✓ Server correctly returns 503 when IP file missing"
else
    echo "✗ Server returned HTTP $HTTP_CODE (expected: 503)"
    exit 1
fi

echo
echo "Test 4: Server updates IP file"
echo "-------------------------------"

# Create new IP file
NEW_IP="198.51.100.99"
echo "$NEW_IP" > "$TEST_DIR/myip.txt"
sleep 1

# Fetch IP
RESPONSE=$(curl -s http://localhost:$TEST_PORT2/ip)
if [ "$RESPONSE" = "$NEW_IP" ]; then
    echo "✓ Server serves updated IP: $RESPONSE"
else
    echo "✗ Server returned unexpected IP: $RESPONSE (expected: $NEW_IP)"
    exit 1
fi

echo
echo "======================================"
echo "All tests passed! ✓"
echo "======================================"
