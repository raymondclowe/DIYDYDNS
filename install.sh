#!/bin/bash
# DIY Dynamic DNS - Automatic Installation Script
# This script auto-detects if it's running on a public server or home network
# and installs the appropriate components.

set -e

echo "=================================================="
echo "DIY Dynamic DNS - Automatic Installation"
echo "=================================================="
echo

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "Please do not run this script as root. Run as a regular user."
    exit 1
fi

# Check for required tools
check_requirements() {
    echo "Checking requirements..."
    
    if ! command -v python3 &> /dev/null; then
        echo "✗ Python 3 is not installed"
        echo "  Please install Python 3: sudo apt install python3"
        exit 1
    fi
    echo "✓ Python 3 found"
    
    if ! command -v curl &> /dev/null; then
        echo "✗ curl is not installed"
        echo "  Please install curl: sudo apt install curl"
        exit 1
    fi
    echo "✓ curl found"
    
    echo
}

# Check if an IP address is private
is_private_ip() {
    local ip=$1
    
    # Check for private IP ranges
    # 10.0.0.0/8
    if [[ $ip =~ ^10\. ]]; then
        return 0
    fi
    # 172.16.0.0/12
    if [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        return 0
    fi
    # 192.168.0.0/16
    if [[ $ip =~ ^192\.168\. ]]; then
        return 0
    fi
    # 127.0.0.0/8 (localhost)
    if [[ $ip =~ ^127\. ]]; then
        return 0
    fi
    
    return 1
}

# Detect if we're on a public server or home network
detect_environment() {
    echo "Detecting environment..."
    
    # Try to get public IP
    PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    
    if [ -z "$PUBLIC_IP" ]; then
        echo "✗ Cannot determine public IP"
        echo "  Please check your internet connection"
        exit 1
    fi
    
    echo "✓ Public IP detected: $PUBLIC_IP"
    
    # Get local IP address
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "")
    
    # Get default gateway
    GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3; exit}' || echo "")
    
    # Auto-detect based on network configuration
    AUTO_DETECTED=""
    
    if [ -n "$LOCAL_IP" ]; then
        echo "  Local IP: $LOCAL_IP"
        if is_private_ip "$LOCAL_IP"; then
            echo "  → Local IP is private (behind NAT/router)"
            AUTO_DETECTED="client"
        else
            echo "  → Local IP is public (directly connected to internet)"
            AUTO_DETECTED="server"
        fi
    fi
    
    if [ -n "$GATEWAY" ]; then
        echo "  Gateway: $GATEWAY"
        if is_private_ip "$GATEWAY"; then
            echo "  → Gateway is private (typical home/office network)"
            AUTO_DETECTED="client"
        fi
    fi
    
    echo
    
    # If auto-detected, use that with confirmation
    if [ -n "$AUTO_DETECTED" ]; then
        echo "Auto-detected: This appears to be a $AUTO_DETECTED machine"
        if [ "$AUTO_DETECTED" = "server" ]; then
            echo "  (Public IP, suitable for hosting the server component)"
        else
            echo "  (Private network, suitable for running the client component)"
        fi
        echo
        read -p "Is this correct? [Y/n] " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
            INSTALL_TYPE="$AUTO_DETECTED"
        else
            AUTO_DETECTED=""
        fi
    fi
    
    # Fall back to manual selection if needed
    if [ -z "$AUTO_DETECTED" ]; then
        echo "Unable to auto-detect environment. Please choose manually:"
        echo "  (Choose 'server' if this has a static IP or is in a datacenter)"
        echo "  (Choose 'client' if this is behind a router/NAT at home)"
        echo
        read -p "Install as [server/client]? " INSTALL_TYPE
        
        case "$INSTALL_TYPE" in
            server|SERVER|s|S)
                INSTALL_TYPE="server"
                ;;
            client|CLIENT|c|C)
                INSTALL_TYPE="client"
                ;;
            *)
                echo "Invalid choice. Please run again and choose 'server' or 'client'"
                exit 1
                ;;
        esac
    fi
    
    echo
    echo "Installing as: $INSTALL_TYPE"
    echo
}

# Install client
install_client() {
    echo "=================================================="
    echo "Installing DIY Dynamic DNS Client (Home Lab)"
    echo "=================================================="
    echo
    
    # Get server details
    read -p "Enter your public server address (user@server.com): " SERVER
    if [ -z "$SERVER" ]; then
        echo "Error: Server address is required"
        exit 1
    fi
    
    read -p "Enter remote path for IP file [/var/www/html/myip.txt]: " REMOTE_PATH
    REMOTE_PATH=${REMOTE_PATH:-/var/www/html/myip.txt}
    
    read -p "Enter check interval in seconds [300]: " INTERVAL
    INTERVAL=${INTERVAL:-300}
    
    # Test SSH connection
    echo
    echo "Testing SSH connection to $SERVER..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" "echo 'SSH OK'" 2>/dev/null; then
        echo "✓ SSH connection successful"
    else
        echo "✗ SSH connection failed"
        echo
        echo "Please set up SSH key authentication:"
        echo "  ssh-keygen -t rsa -b 4096"
        echo "  ssh-copy-id $SERVER"
        echo
        read -p "Press Enter to continue anyway, or Ctrl+C to exit..."
    fi
    
    # Install files
    echo
    echo "Installing files..."
    sudo mkdir -p /opt/diydydns
    sudo cp client.py /opt/diydydns/
    sudo chmod +x /opt/diydydns/client.py
    echo "✓ Client script installed to /opt/diydydns/"
    
    # Create config
    sudo mkdir -p /etc/diydydns
    sudo tee /etc/diydydns/client.conf > /dev/null <<EOF
# DIY Dynamic DNS Client Configuration
SERVER=$SERVER
REMOTE_PATH=$REMOTE_PATH
INTERVAL=$INTERVAL
EOF
    echo "✓ Configuration saved to /etc/diydydns/client.conf"
    
    # Install systemd service
    if command -v systemctl &> /dev/null; then
        sudo cp systemd/diydydns-client@.service /etc/systemd/system/
        sudo systemctl daemon-reload
        echo "✓ Systemd service installed"
        
        echo
        read -p "Enable and start the service now? [Y/n] " START_NOW
        if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
            sudo systemctl enable diydydns-client@$USER.service
            sudo systemctl start diydydns-client@$USER.service
            echo "✓ Service started"
            echo
            echo "Check status with: sudo systemctl status diydydns-client@$USER.service"
        fi
    else
        echo "⚠ systemd not found. You can set up cron instead (see CRON_SETUP.md)"
    fi
    
    echo
    echo "=================================================="
    echo "Client installation complete!"
    echo "=================================================="
    echo "Your home lab will now update the server when your IP changes."
}

# Detect installed reverse proxies
detect_reverse_proxies() {
    local proxies=()
    
    if command -v nginx &> /dev/null; then
        proxies+=("nginx")
    fi
    
    if command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then
        proxies+=("apache")
    fi
    
    if command -v caddy &> /dev/null; then
        proxies+=("caddy")
    fi
    
    echo "${proxies[@]}"
}

# Check if a port is in use
is_port_in_use() {
    local port=$1
    
    # Check with netstat or ss
    if command -v netstat &> /dev/null; then
        if netstat -tln 2>/dev/null | grep -q ":$port "; then
            return 0
        fi
    fi
    
    if command -v ss &> /dev/null; then
        if ss -tln 2>/dev/null | grep -q ":$port "; then
            return 0
        fi
    fi
    
    return 1
}

# Suggest an available port
suggest_available_port() {
    local default_port=$1
    local suggested_ports=("$default_port" 8080 8081 8082 3000 3001 5000 5001)
    
    for port in "${suggested_ports[@]}"; do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    # If all common ports are taken, suggest a random high port
    echo $((10000 + RANDOM % 10000))
}

# Install server
install_server() {
    echo "=================================================="
    echo "Installing DIY Dynamic DNS Server (Public Server)"
    echo "=================================================="
    echo
    
    # Detect reverse proxies
    PROXIES=($(detect_reverse_proxies))
    
    if [ ${#PROXIES[@]} -gt 0 ]; then
        echo "Detected reverse proxy: ${PROXIES[@]}"
        echo "You can use your reverse proxy to serve the IP file instead of running"
        echo "the Python server. Configuration examples will be shown at the end."
        echo
    fi
    
    # Suggest an available port
    DEFAULT_PORT=8080
    if is_port_in_use "$DEFAULT_PORT"; then
        SUGGESTED_PORT=$(suggest_available_port "$DEFAULT_PORT")
        echo "⚠ Port $DEFAULT_PORT is already in use"
        echo "  Suggested alternative: $SUGGESTED_PORT"
        read -p "Enter port to listen on [$SUGGESTED_PORT]: " PORT
        PORT=${PORT:-$SUGGESTED_PORT}
    else
        read -p "Enter port to listen on [$DEFAULT_PORT]: " PORT
        PORT=${PORT:-$DEFAULT_PORT}
    fi
    
    # Warn if chosen port is in use
    if is_port_in_use "$PORT"; then
        echo "⚠ Warning: Port $PORT appears to be in use"
        read -p "Continue anyway? [y/N] " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 1
        fi
    fi
    
    read -p "Enter path for IP file [/var/www/html/myip.txt]: " IP_FILE
    IP_FILE=${IP_FILE:-/var/www/html/myip.txt}
    
    # Create directory with proper permissions
    echo
    echo "Setting up directories and permissions..."
    sudo mkdir -p "$(dirname "$IP_FILE")"
    
    # Set up shared access
    if id www-data &>/dev/null; then
        sudo usermod -a -G www-data $USER
        sudo chown $USER:www-data "$(dirname "$IP_FILE")"
        sudo chmod 775 "$(dirname "$IP_FILE")"
        echo "✓ Permissions set for shared access (www-data group)"
        echo "  Note: You may need to log out and back in for group changes to take effect"
    else
        sudo chown $USER:$USER "$(dirname "$IP_FILE")"
        echo "✓ Directory created and owned by $USER"
    fi
    
    # Install files
    echo
    echo "Installing files..."
    sudo mkdir -p /opt/diydydns
    sudo cp server.py /opt/diydydns/
    sudo chmod +x /opt/diydydns/server.py
    echo "✓ Server script installed to /opt/diydydns/"
    
    # Create config
    sudo mkdir -p /etc/diydydns
    sudo tee /etc/diydydns/server.conf > /dev/null <<EOF
# DIY Dynamic DNS Server Configuration
PORT=$PORT
IP_FILE=$IP_FILE
BIND_ADDRESS=0.0.0.0
EOF
    echo "✓ Configuration saved to /etc/diydydns/server.conf"
    
    # Install systemd service
    if command -v systemctl &> /dev/null; then
        sudo cp systemd/diydydns-server.service /etc/systemd/system/
        sudo systemctl daemon-reload
        echo "✓ Systemd service installed"
        
        echo
        read -p "Enable and start the service now? [Y/n] " START_NOW
        if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
            sudo systemctl enable diydydns-server.service
            sudo systemctl start diydydns-server.service
            echo "✓ Service started"
            echo
            echo "Check status with: sudo systemctl status diydydns-server.service"
        fi
    else
        echo "⚠ systemd not found"
    fi
    
    # Check firewall
    echo
    if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
        echo "Firewall detected. You may need to allow port $PORT:"
        echo "  sudo ufw allow $PORT"
    fi
    
    # Show reverse proxy configurations if detected
    if [ ${#PROXIES[@]} -gt 0 ]; then
        echo
        echo "=================================================="
        echo "Reverse Proxy Configuration Examples"
        echo "=================================================="
        echo
        echo "You can use your reverse proxy to serve the IP file instead of"
        echo "running the Python server on port $PORT."
        echo
        
        for proxy in "${PROXIES[@]}"; do
            case "$proxy" in
                nginx)
                    echo "─────────────────────────────────────────────────"
                    echo "Nginx Configuration:"
                    echo "─────────────────────────────────────────────────"
                    echo "Add this to your Nginx configuration:"
                    echo
                    cat << 'EOF'
server {
    listen 80;
    server_name your-domain.com;
    
    location /ip {
        alias /var/www/html/myip.txt;
        default_type text/plain;
        add_header Access-Control-Allow-Origin *;
    }
}
EOF
                    echo
                    echo "Then reload: sudo systemctl reload nginx"
                    echo
                    ;;
                apache)
                    echo "─────────────────────────────────────────────────"
                    echo "Apache Configuration:"
                    echo "─────────────────────────────────────────────────"
                    echo "Add this to your Apache configuration:"
                    echo
                    cat << 'EOF'
<VirtualHost *:80>
    ServerName your-domain.com
    
    Alias /ip /var/www/html/myip.txt
    
    <Location /ip>
        ForceType text/plain
        Header set Access-Control-Allow-Origin "*"
    </Location>
</VirtualHost>
EOF
                    echo
                    echo "Enable required modules and reload:"
                    echo "  sudo a2enmod headers"
                    echo "  sudo systemctl reload apache2"
                    echo
                    ;;
                caddy)
                    echo "─────────────────────────────────────────────────"
                    echo "Caddy Configuration:"
                    echo "─────────────────────────────────────────────────"
                    echo "Add this to your Caddyfile:"
                    echo
                    cat << 'EOF'
your-domain.com {
    route /ip {
        header Access-Control-Allow-Origin *
        rewrite * /myip.txt
        file_server {
            root /var/www/html
        }
    }
}
EOF
                    echo
                    echo "Then reload: sudo systemctl reload caddy"
                    echo
                    ;;
            esac
        done
        
        echo "Note: If using a reverse proxy, you can skip starting the Python"
        echo "      server service and use only the client component."
    fi
    
    echo
    echo "=================================================="
    echo "Server installation complete!"
    echo "=================================================="
    if [ ${#PROXIES[@]} -eq 0 ]; then
        echo "Access your IP at: http://$(curl -s ifconfig.me):$PORT/ip"
    else
        echo "Configure your reverse proxy (see above) or access via Python server:"
        echo "  http://$(curl -s ifconfig.me):$PORT/ip"
    fi
    echo
    echo "Next, install the client on your home lab machine."
}

# Main installation flow
main() {
    check_requirements
    detect_environment
    
    if [ "$INSTALL_TYPE" = "server" ]; then
        install_server
    else
        install_client
    fi
    
    echo
    echo "Installation finished successfully!"
    echo
    echo "For more information, see README.md"
}

main
