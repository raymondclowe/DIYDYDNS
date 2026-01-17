# DIYDYDNS - DIY Dynamic DNS

This is a DIY Dynamic DNS solution with two parts:
1. **Client** - Runs on your home lab to monitor and update your public IP
2. **Server** - Runs on your public server to store and serve your current IP

## Overview

The home lab client periodically checks your public IP address using external services like `ifconfig.me` or `api.ipify.org`. When the IP changes, it securely transfers the new IP to your public server via SCP (SSH). The server component provides a simple HTTP endpoint that you can query from anywhere to get your current home IP address.

## Quick Install

**Easy one-liner installation (recommended):**

```bash
# Run this on both your home lab and public server
curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/raymondclowe/DIYDYDNS.git
cd DIYDYDNS
./install.sh
```

The script will auto-detect whether you're on a public server or home network and install the appropriate components.

**For non-interactive client installation (e.g., in automation scripts):**

```bash
# Set environment variable with export, then pipe to bash
# This ensures the variable is available to the script running in the subshell
export DIYDYDNS_SERVER=user@server.com && curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash

# Optional: customize other settings
export DIYDYDNS_SERVER=user@server.com
export DIYDYDNS_REMOTE_PATH=/var/www/html/myip.txt
export DIYDYDNS_INTERVAL=300
curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash
```

**Note:** When piping to bash, environment variables need to be exported first to be available in the subshell created by the pipe.

**For non-interactive server installation:**

```bash
# Server installation with defaults
curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash

# Optional: customize port and IP file location
DIYDYDNS_PORT=8080 \
DIYDYDNS_IP_FILE=/var/www/html/myip.txt \
curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash
```

**Note for Cloud Providers (AWS, GCP, Azure, Oracle Cloud):**

The installer automatically detects cloud instances by checking for cloud metadata services. If you're running on a cloud instance with a private local IP (e.g., 10.x.x.x) but a public IP assigned by the cloud provider, the script will correctly identify it as a server. The detection works for:
- AWS EC2 instances
- Google Cloud Compute Engine instances  
- Azure Virtual Machines
- Oracle Cloud instances

If the auto-detection fails, you can force server installation in non-interactive mode by setting `DIYDYDNS_FORCE_TYPE`:
```bash
DIYDYDNS_FORCE_TYPE=server curl -fsSL https://raw.githubusercontent.com/raymondclowe/DIYDYDNS/main/install.sh | bash
```

**Note:** The installer will detect if components are already installed and skip reinstallation in non-interactive mode.

## Features

- 🔄 Automatic IP monitoring with configurable intervals
- 🔒 Secure transfer via SCP/SSH
- 🌐 Simple HTTP API to retrieve your IP
- 📝 Caching to avoid unnecessary updates
- 🔁 Auto-restart on failure
- 🐧 Systemd service examples included
- 🚀 One-line installation script

## Requirements

### Client (Home Lab)
- Python 3.6+
- `curl` command-line tool
- SSH access to your public server
- SSH key-based authentication (recommended)

### Server (Public Server)
- Python 3.6+
- SSH server running
- Open port for HTTP service (default: 8080)

## Quick Start

### 1. Setup on Public Server

```bash
# Copy the server script
scp server.py user@your-server.com:/opt/diydydns/

# SSH into your server
ssh user@your-server.com

# Create the IP file directory and set permissions
sudo mkdir -p /var/www/html

# Set up permissions for shared access between SSH user and server
# Option 1: If running server as current user
sudo chown $USER:$USER /var/www/html

# Option 2: If running server as www-data (recommended for production)
# Add your user to www-data group and set group permissions
sudo usermod -a -G www-data $USER
sudo chown $USER:www-data /var/www/html
sudo chmod 775 /var/www/html
# Note: You may need to log out and back in for group changes to take effect

# Start the server (for testing)
python3 /opt/diydydns/server.py --port 8080 --ip-file /var/www/html/myip.txt
```

### 2. Setup on Home Lab

```bash
# Setup SSH key authentication (if not already done)
ssh-keygen -t rsa -b 4096
ssh-copy-id user@your-server.com

# Test the connection
ssh user@your-server.com 'echo "test" > /var/www/html/myip.txt'

# Run the client (for testing)
python3 client.py --server user@your-server.com --remote-path /var/www/html/myip.txt --once
```

### 3. Check Your IP

From anywhere, retrieve your home IP:

```bash
# Using curl
curl http://your-server.com:8080/ip

# Using web browser
# Navigate to: http://your-server.com:8080/ip
```

## Usage

### Client Options

```bash
python3 client.py --help

Options:
  --server SERVER         Server address (e.g., user@server.com) [REQUIRED]
  --remote-path PATH      Remote path to store IP file (default: /var/www/html/myip.txt)
  --interval SECONDS      Check interval in seconds (default: 300)
  --cache-file PATH       Local cache file for IP (default: ~/.diydydns/cached_ip.txt)
  --ssh-key PATH          Path to SSH private key for authentication
  --once                  Run once and exit (for testing)
```

### Server Options

```bash
python3 server.py --help

Options:
  --port PORT            Port to listen on (default: 8080)
  --ip-file PATH         Path to IP file (default: /var/www/html/myip.txt)
  --bind ADDRESS         Address to bind to (default: 0.0.0.0)
```

## Running as a Service

### Systemd Installation

#### On Home Lab (Client)

```bash
# Copy service file
sudo cp systemd/diydydns-client@.service /etc/systemd/system/

# Create config directory and copy config file
sudo mkdir -p /etc/diydydns
sudo cp systemd/client.conf.example /etc/diydydns/client.conf

# Edit the configuration file with your server details
sudo nano /etc/diydydns/client.conf

# Enable and start the service
sudo systemctl enable diydydns-client@$USER.service
sudo systemctl start diydydns-client@$USER.service

# Check status
sudo systemctl status diydydns-client@$USER.service
```

#### On Public Server

```bash
# Copy service file
sudo cp systemd/diydydns-server.service /etc/systemd/system/

# Create config directory and copy config file
sudo mkdir -p /etc/diydydns
sudo cp systemd/server.conf.example /etc/diydydns/server.conf

# Edit the configuration file if needed
sudo nano /etc/diydydns/server.conf

# Enable and start the service
sudo systemctl enable diydydns-server.service
sudo systemctl start diydydns-server.service

# Check status
sudo systemctl status diydydns-server.service
```

## Alternative: Using with a Reverse Proxy

You can use a reverse proxy (Nginx, Apache, or Caddy) to serve the IP file instead of the Python server:

### Nginx

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location /ip {
        alias /var/www/html/myip.txt;
        default_type text/plain;
        add_header Access-Control-Allow-Origin *;
    }
}
```

### Apache

```apache
<VirtualHost *:80>
    ServerName your-domain.com
    
    Alias /ip /var/www/html/myip.txt
    
    <Location /ip>
        ForceType text/plain
        Header set Access-Control-Allow-Origin "*"
    </Location>
</VirtualHost>
```

Enable required modules:
```bash
sudo a2enmod headers
sudo systemctl reload apache2
```

### Caddy

```caddy
your-domain.com {
    route /ip {
        header Access-Control-Allow-Origin *
        rewrite * /myip.txt
        file_server {
            root /var/www/html
        }
    }
}
```

Reload Caddy:
```bash
sudo systemctl reload caddy
```

With any of these reverse proxies configured, you only need to run the client component, and query: `curl http://your-domain.com/ip`

## Troubleshooting

### Client Issues

**"Failed to get public IP address"**
- Check your internet connection
- Verify curl is installed: `which curl`
- Try manually: `curl https://ifconfig.me`

**"Failed to update server"**
- Verify SSH connection: `ssh user@your-server.com`
- Check SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
- Test SCP manually: `echo "test" > /tmp/test.txt && scp /tmp/test.txt user@your-server.com:/var/www/html/myip.txt`

### Server Issues

**"Permission denied"**
- Ensure the IP file path is writable by both the SSH user and the server process
- Check directory permissions: `ls -la /var/www/html/`
- If running server as www-data, ensure proper group permissions:
  ```bash
  sudo usermod -a -G www-data your-ssh-user
  sudo chown your-ssh-user:www-data /var/www/html
  sudo chmod 775 /var/www/html
  # Log out and back in for group changes to take effect
  ```
- Use a port > 1024 or run as root (not recommended)

**Can't connect to server**
- Check firewall: `sudo ufw allow 8080`
- Verify server is listening: `netstat -tlnp | grep 8080`

## Security Considerations

1. **SSH Keys**: Always use SSH key authentication instead of passwords
2. **Firewall**: Limit SSH access to known IPs if possible
3. **File Permissions**: Ensure the IP file is readable by the web server but not world-writable
4. **HTTPS**: Consider using Nginx with Let's Encrypt for HTTPS access to the IP endpoint
5. **Rate Limiting**: The client respects a minimum interval to avoid excessive requests

## How It Works

```
┌─────────────────┐                    ┌──────────────────┐
│   Home Lab      │                    │  Public Server   │
│                 │                    │                  │
│  ┌──────────┐   │                    │  ┌───────────┐   │
│  │ client.py│───┼───── SCP/SSH ─────→│  │  myip.txt │   │
│  └──────────┘   │    (when IP       │  └─────┬─────┘   │
│       ↓         │     changes)       │        │         │
│  Check IP via   │                    │        ↓         │
│  curl every     │                    │  ┌───────────┐   │
│  5 minutes      │                    │  │ server.py │   │
│                 │                    │  └─────┬─────┘   │
└─────────────────┘                    └────────┼─────────┘
                                                 │
                                                 ↓
                                    ┌────────────────────┐
                                    │  HTTP GET /ip      │
                                    │  Returns: 1.2.3.4  │
                                    └────────────────────┘
```

## License

MIT License - Feel free to use and modify as needed!

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.
