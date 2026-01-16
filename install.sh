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
    
    # Check if we can accept incoming connections (likely a server)
    # For now, we'll ask the user
    echo
    echo "Is this machine publicly accessible from the internet?"
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

# Install server
install_server() {
    echo "=================================================="
    echo "Installing DIY Dynamic DNS Server (Public Server)"
    echo "=================================================="
    echo
    
    read -p "Enter port to listen on [8080]: " PORT
    PORT=${PORT:-8080}
    
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
    
    echo
    echo "=================================================="
    echo "Server installation complete!"
    echo "=================================================="
    echo "Access your IP at: http://$(curl -s ifconfig.me):$PORT/ip"
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
