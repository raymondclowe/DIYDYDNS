#!/usr/bin/env python3
"""
DIY Dynamic DNS - Server (Public Server)

This script runs on your public server and provides a simple HTTP endpoint
to retrieve the current IP address of your home lab.
"""

import http.server
import socketserver
import argparse
import os
import sys
import ipaddress


class IPAddressHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler to serve the IP address."""
    
    ip_file = None
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/' or self.path == '/ip':
            self.send_ip()
        elif self.path == '/health':
            self.send_health()
        else:
            self.send_error(404, "Not Found")
    
    def send_ip(self):
        """Send the current IP address."""
        try:
            if os.path.exists(self.ip_file):
                with open(self.ip_file, 'r') as f:
                    ip = f.read().strip()
                
                # Validate IP address before serving
                try:
                    ipaddress.IPv4Address(ip)
                except ipaddress.AddressValueError:
                    print(f"Invalid IP address in file: {ip}", file=sys.stderr)
                    self.send_error(500, "Invalid IP address format")
                    return
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                # Note: Using wildcard CORS for public DNS service access
                # If you need to restrict this, configure the allowed origins
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(ip.encode())
            else:
                self.send_error(503, "IP address not available")
        except Exception as e:
            print(f"Error reading IP file: {e}", file=sys.stderr)
            self.send_error(500, "Internal Server Error")
    
    def send_health(self):
        """Health check endpoint."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"OK")
    
    def log_message(self, format, *args):
        """Log requests to stdout."""
        sys.stdout.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format % args))


def main():
    parser = argparse.ArgumentParser(
        description='DIY Dynamic DNS Server - Serves your home lab public IP'
    )
    parser.add_argument(
        '--port',
        type=int,
        default=8080,
        help='Port to listen on (default: 8080)'
    )
    parser.add_argument(
        '--ip-file',
        default='/var/www/html/myip.txt',
        help='Path to IP file (default: /var/www/html/myip.txt)'
    )
    parser.add_argument(
        '--bind',
        default='0.0.0.0',
        help='Address to bind to (default: 0.0.0.0)'
    )
    
    args = parser.parse_args()
    
    # Set the IP file path for the handler
    IPAddressHandler.ip_file = args.ip_file
    
    # Create directory if it doesn't exist
    os.makedirs(os.path.dirname(args.ip_file) or '.', exist_ok=True)
    
    try:
        with socketserver.TCPServer((args.bind, args.port), IPAddressHandler) as httpd:
            print(f"DIY Dynamic DNS Server starting...")
            print(f"Listening on {args.bind}:{args.port}")
            print(f"IP file: {args.ip_file}")
            print(f"Access your IP at: http://<server>:{args.port}/ip")
            httpd.serve_forever()
    except PermissionError:
        print(f"Error: Permission denied. Port {args.port} may require root privileges.", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error starting server: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nShutting down server...")
        sys.exit(0)


if __name__ == '__main__':
    main()
