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

# Check if running interactively
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
    echo "Running in non-interactive mode (piped from curl)"
    echo
fi

# Download repository files if needed (for curl | bash installation)
download_repository() {
    # Check if required files exist in current directory
    if [ -f "client.py" ] && [ -f "server.py" ] && [ -d "systemd" ]; then
        # Files already exist, likely running from cloned repo
        echo "✓ Repository files found in current directory"
        return 0
    fi
    
    # Need to download the repository
    echo "Downloading DIYDYDNS repository files..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    if ! cd "$TEMP_DIR"; then
        echo "✗ Failed to change to temporary directory"
        # Safe cleanup: cd to / and validate before removing
        cd / 2>/dev/null || true
        [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Download and extract the repository
    if ! curl -fsSL https://github.com/raymondclowe/DIYDYDNS/archive/main.tar.gz | tar xz; then
        echo "✗ Failed to download repository files"
        cd / 2>/dev/null || true
        [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Move into extracted directory
    if ! cd DIYDYDNS-main; then
        echo "✗ Failed to access extracted repository"
        cd / 2>/dev/null || true
        [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo "✓ Repository files downloaded"
    
    # Set flag that we downloaded files
    DOWNLOADED_REPO=true
}

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

# Check if client or server is already installed
check_existing_installation() {
    local component=$1
    
    if [ "$component" = "client" ]; then
        if [ -f "/opt/diydydns/client.py" ] && [ -f "/etc/diydydns/client.conf" ]; then
            echo "⚠ Client is already installed"
            echo "  Script: /opt/diydydns/client.py"
            echo "  Config: /etc/diydydns/client.conf"
            
            if command -v systemctl &> /dev/null; then
                # Check if service is enabled (not running status, just enabled at boot)
                if systemctl is-enabled diydydns-client@*.service &>/dev/null; then
                    echo "  Service: Enabled"
                fi
            fi
            
            echo
            if [ "$INTERACTIVE" = true ]; then
                read -p "Reinstall? This will overwrite existing configuration. [y/N] " REINSTALL
                if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
                    echo "Installation cancelled. Existing installation kept."
                    exit 0
                fi
            else
                echo "Skipping installation. Already installed."
                exit 0
            fi
        fi
    elif [ "$component" = "server" ]; then
        if [ -f "/opt/diydydns/server.py" ] && [ -f "/etc/diydydns/server.conf" ]; then
            echo "⚠ Server is already installed"
            echo "  Script: /opt/diydydns/server.py"
            echo "  Config: /etc/diydydns/server.conf"
            
            if command -v systemctl &> /dev/null; then
                # Check if service is enabled (not running status, just enabled at boot)
                if systemctl is-enabled diydydns-server.service &>/dev/null; then
                    echo "  Service: Enabled"
                fi
            fi
            
            echo
            if [ "$INTERACTIVE" = true ]; then
                read -p "Reinstall? This will overwrite existing configuration. [y/N] " REINSTALL
                if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
                    echo "Installation cancelled. Existing installation kept."
                    exit 0
                fi
            else
                echo "Skipping installation. Already installed."
                exit 0
            fi
        fi
    fi
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
            
            # Check if this is a cloud instance with NAT
            # Cloud providers (AWS, GCP, Azure, Oracle Cloud) use NAT to map
            # public IPs to private IPs on instances
            # If we can reach the internet and the public IP differs from local IP,
            # this is likely a cloud server
            if [ "$PUBLIC_IP" != "$LOCAL_IP" ]; then
                # Check if common cloud metadata services are accessible
                # Try AWS first (most common), then Azure (same IP), then GCP
                if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/ &>/dev/null || \
                   curl -s --max-time 2 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-12-13 &>/dev/null || \
                   curl -s --max-time 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
                    echo "  → Cloud instance detected (AWS/GCP/Azure/Oracle)"
                    AUTO_DETECTED="server"
                else
                    # Could be home network behind NAT or cloud without metadata service
                    AUTO_DETECTED="client"
                fi
            else
                AUTO_DETECTED="client"
            fi
        else
            echo "  → Local IP is public (directly connected to internet)"
            AUTO_DETECTED="server"
        fi
    fi
    
    if [ -n "$GATEWAY" ]; then
        echo "  Gateway: $GATEWAY"
        if is_private_ip "$GATEWAY"; then
            echo "  → Gateway is private"
            # Only override to client if not already detected as server
            # This preserves cloud instance detection above
            if [ "$AUTO_DETECTED" != "server" ]; then
                echo "  → Typical home/office network configuration"
                AUTO_DETECTED="client"
            else
                echo "  → Typical cloud instance configuration"
            fi
        fi
    fi
    
    echo
    
    # Check if type is forced via environment variable
    if [ -n "${DIYDYDNS_FORCE_TYPE:-}" ]; then
        # Trim leading and trailing whitespace to handle user input errors
        # Using shell parameter expansion for safety
        DIYDYDNS_FORCE_TYPE="${DIYDYDNS_FORCE_TYPE#"${DIYDYDNS_FORCE_TYPE%%[![:space:]]*}"}"
        DIYDYDNS_FORCE_TYPE="${DIYDYDNS_FORCE_TYPE%"${DIYDYDNS_FORCE_TYPE##*[![:space:]]}"}"
        case "${DIYDYDNS_FORCE_TYPE}" in
            server|SERVER)
                INSTALL_TYPE="server"
                echo "Installation type forced to: server (via DIYDYDNS_FORCE_TYPE)"
                echo
                return
                ;;
            client|CLIENT)
                INSTALL_TYPE="client"
                echo "Installation type forced to: client (via DIYDYDNS_FORCE_TYPE)"
                echo
                return
                ;;
            *)
                echo "⚠ Warning: Invalid DIYDYDNS_FORCE_TYPE value: ${DIYDYDNS_FORCE_TYPE}"
                echo "  Valid values are: server, client"
                echo "  Continuing with auto-detection..."
                echo
                ;;
        esac
    fi
    
    # If auto-detected, use that with confirmation (or auto-proceed if non-interactive)
    if [ -n "$AUTO_DETECTED" ]; then
        echo "Auto-detected: This appears to be a $AUTO_DETECTED machine"
        if [ "$AUTO_DETECTED" = "server" ]; then
            echo "  (Public IP, suitable for hosting the server component)"
        else
            echo "  (Private network, suitable for running the client component)"
        fi
        echo
        
        if [ "$INTERACTIVE" = true ]; then
            read -p "Is this correct? [Y/n] " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
                INSTALL_TYPE="$AUTO_DETECTED"
                echo
                echo "Installing as: $INSTALL_TYPE"
                echo
                return
            fi
        else
            # Non-interactive mode: proceed with auto-detection
            INSTALL_TYPE="$AUTO_DETECTED"
            echo "Proceeding with auto-detected type: $INSTALL_TYPE"
            echo
            return
        fi
    fi
    
    # Manual selection (either no auto-detection or user rejected)
    if [ "$INTERACTIVE" = false ]; then
        echo "Error: Cannot proceed in non-interactive mode without auto-detection"
        echo "Please run the script locally with ./install.sh for manual selection"
        exit 1
    fi
    
    if [ -n "$AUTO_DETECTED" ]; then
        echo "Please choose manually:"
    else
        echo "Unable to auto-detect environment. Please choose manually:"
    fi
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
    
    # Check if already installed
    check_existing_installation "client"
    
    # Get server details
    if [ "$INTERACTIVE" = true ]; then
        read -p "Enter your public server address (user@server.com): " SERVER
        if [ -z "$SERVER" ]; then
            echo "Error: Server address is required"
            exit 1
        fi
        
        read -p "Enter remote path for IP file [/var/www/html/myip.txt]: " REMOTE_PATH
        REMOTE_PATH=${REMOTE_PATH:-/var/www/html/myip.txt}
        
        read -p "Enter check interval in seconds [300]: " INTERVAL
        INTERVAL=${INTERVAL:-300}
    else
        # Non-interactive mode: use defaults or environment variables
        SERVER="${DIYDYDNS_SERVER:-}"
        REMOTE_PATH="${DIYDYDNS_REMOTE_PATH:-/var/www/html/myip.txt}"
        INTERVAL="${DIYDYDNS_INTERVAL:-300}"
        
        if [ -z "$SERVER" ]; then
            echo "Error: Server address is required for non-interactive installation"
            echo "Please set DIYDYDNS_SERVER environment variable or run interactively"
            echo
            echo "Example:"
            echo "  DIYDYDNS_SERVER=user@server.com curl -fsSL ... | bash"
            echo
            echo "Or run locally for interactive setup:"
            echo "  git clone https://github.com/raymondclowe/DIYDYDNS.git"
            echo "  cd DIYDYDNS"
            echo "  ./install.sh"
            exit 1
        fi
        
        echo "Using configuration:"
        echo "  Server: $SERVER"
        echo "  Remote path: $REMOTE_PATH"
        echo "  Interval: $INTERVAL seconds"
        echo
    fi
    
    # Test SSH connection
    if [ "$INTERACTIVE" = true ]; then
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
    else
        echo "Note: Skipping SSH connection test in non-interactive mode"
        echo "      Ensure SSH key authentication is set up before running the client"
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
        
        if [ "$INTERACTIVE" = true ]; then
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
            # Non-interactive mode: auto-enable and start
            sudo systemctl enable diydydns-client@$USER.service
            sudo systemctl start diydydns-client@$USER.service
            echo "✓ Service enabled and started"
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
        if netstat -tln 2>/dev/null | grep -qE ":${port}($|[[:space:]])"; then
            return 0
        fi
    fi
    
    if command -v ss &> /dev/null; then
        if ss -tln 2>/dev/null | grep -qE ":${port}($|[[:space:]])"; then
            return 0
        fi
    fi
    
    return 1
}

# Suggest an available port
suggest_available_port() {
    local suggested_ports=(8081 8082 3000 3001 5000 5001)
    
    # Try common ports
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
    
    # Check if already installed
    check_existing_installation "server"
    
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
    if [ "$INTERACTIVE" = true ]; then
        if is_port_in_use "$DEFAULT_PORT"; then
            # Default port is in use, suggest an alternative
            SUGGESTED_PORT=$(suggest_available_port)
            echo "⚠ Port $DEFAULT_PORT is already in use"
            echo "  Suggested alternative: $SUGGESTED_PORT"
            read -p "Enter port to listen on [$SUGGESTED_PORT]: " PORT
            PORT=${PORT:-$SUGGESTED_PORT}
        else
            # Default port is available
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
    else
        # Non-interactive mode: use defaults or environment variables
        PORT="${DIYDYDNS_PORT:-$DEFAULT_PORT}"
        IP_FILE="${DIYDYDNS_IP_FILE:-/var/www/html/myip.txt}"
        
        if is_port_in_use "$PORT"; then
            SUGGESTED_PORT=$(suggest_available_port)
            echo "⚠ Port $PORT is already in use"
            echo "  Using alternative port: $SUGGESTED_PORT"
            PORT=$SUGGESTED_PORT
        fi
        
        echo "Using configuration:"
        echo "  Port: $PORT"
        echo "  IP file: $IP_FILE"
        echo
    fi
    
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
        
        if [ "$INTERACTIVE" = true ]; then
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
            # Non-interactive mode: auto-enable and start
            sudo systemctl enable diydydns-server.service
            sudo systemctl start diydydns-server.service
            echo "✓ Service enabled and started"
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
    download_repository
    detect_environment
    
    if [ "$INSTALL_TYPE" = "server" ]; then
        install_server
    else
        install_client
    fi
    
    # Cleanup temporary directory if we downloaded files
    if [ "${DOWNLOADED_REPO:-false}" = true ] && [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        # Extra safety: verify TEMP_DIR is actually a temp directory
        case "$TEMP_DIR" in
            /tmp/*|/var/tmp/*)
                cd / 2>/dev/null || true
                rm -rf "$TEMP_DIR"
                ;;
            *)
                echo "⚠ Warning: Skipping cleanup of unexpected temp directory: $TEMP_DIR"
                ;;
        esac
    fi
    
    echo
    echo "Installation finished successfully!"
    echo
    echo "For more information, see README.md"
}

main
