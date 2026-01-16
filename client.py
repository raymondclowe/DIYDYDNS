#!/usr/bin/env python3
"""
DIY Dynamic DNS - Client (Home Lab)

This script runs on your home lab and periodically checks your public IP address.
When the IP changes, it updates the public server via SCP.
"""

import subprocess
import sys
import time
import os
import argparse
import ipaddress
import tempfile


def get_public_ip():
    """Get the current public IP address using an external service."""
    services = [
        'https://ifconfig.me',
        'https://api.ipify.org',
        'https://icanhazip.com',
        'https://checkip.amazonaws.com'
    ]
    
    for service in services:
        try:
            result = subprocess.run(
                ['curl', '-s', '--max-time', '5', service],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0 and result.stdout.strip():
                ip_str = result.stdout.strip()
                # Validate IPv4 address
                try:
                    ipaddress.IPv4Address(ip_str)
                    return ip_str
                except ipaddress.AddressValueError:
                    continue
        except Exception as e:
            print(f"Failed to get IP from {service}: {e}", file=sys.stderr)
            continue
    
    return None


def read_cached_ip(cache_file):
    """Read the cached IP address from file."""
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'r') as f:
                return f.read().strip()
        except Exception as e:
            print(f"Error reading cache: {e}", file=sys.stderr)
    return None


def write_cached_ip(cache_file, ip):
    """Write the IP address to cache file."""
    try:
        os.makedirs(os.path.dirname(cache_file) or '.', exist_ok=True)
        with open(cache_file, 'w') as f:
            f.write(ip)
        return True
    except Exception as e:
        print(f"Error writing cache: {e}", file=sys.stderr)
        return False


def update_server(ip, server, remote_path, ssh_key=None, strict_host_key_checking=True):
    """Update the public server with the new IP address via SCP."""
    # Create temporary file with IP using secure method
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
            temp_file = f.name
            f.write(ip)
        
        # Build SCP command
        cmd = ['scp']
        if ssh_key:
            cmd.extend(['-i', ssh_key])
        if not strict_host_key_checking:
            cmd.extend(['-o', 'StrictHostKeyChecking=no'])
        cmd.extend([temp_file, f"{server}:{remote_path}"])
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            print(f"Successfully updated server with IP: {ip}")
            return True
        else:
            print(f"Failed to update server: {result.stderr}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error updating server: {e}", file=sys.stderr)
        return False
    finally:
        if 'temp_file' in locals() and os.path.exists(temp_file):
            os.remove(temp_file)


def main():
    parser = argparse.ArgumentParser(
        description='DIY Dynamic DNS Client - Monitors and updates your public IP'
    )
    parser.add_argument(
        '--server',
        required=True,
        help='Server address (e.g., user@server.com)'
    )
    parser.add_argument(
        '--remote-path',
        default='/var/www/html/myip.txt',
        help='Remote path to store IP file (default: /var/www/html/myip.txt)'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=300,
        help='Check interval in seconds (default: 300)'
    )
    parser.add_argument(
        '--cache-file',
        default=os.path.expanduser('~/.diydydns/cached_ip.txt'),
        help='Local cache file for IP (default: ~/.diydydns/cached_ip.txt)'
    )
    parser.add_argument(
        '--ssh-key',
        help='Path to SSH private key for authentication'
    )
    parser.add_argument(
        '--disable-host-key-check',
        action='store_true',
        help='Disable SSH host key checking (NOT RECOMMENDED for security)'
    )
    parser.add_argument(
        '--once',
        action='store_true',
        help='Run once and exit (default: run continuously)'
    )
    
    args = parser.parse_args()
    
    print(f"Starting DIY Dynamic DNS Client")
    print(f"Server: {args.server}")
    print(f"Remote path: {args.remote_path}")
    print(f"Check interval: {args.interval} seconds")
    print(f"Cache file: {args.cache_file}")
    
    while True:
        try:
            current_ip = get_public_ip()
            
            if not current_ip:
                print("Failed to get public IP address", file=sys.stderr)
            else:
                print(f"Current public IP: {current_ip}")
                cached_ip = read_cached_ip(args.cache_file)
                
                if current_ip != cached_ip:
                    print(f"IP changed from {cached_ip} to {current_ip}")
                    if update_server(current_ip, args.server, args.remote_path, args.ssh_key, 
                                   not args.disable_host_key_check):
                        write_cached_ip(args.cache_file, current_ip)
                    else:
                        print("Failed to update server", file=sys.stderr)
                else:
                    print("IP unchanged")
            
            if args.once:
                break
            
            time.sleep(args.interval)
            
        except KeyboardInterrupt:
            print("\nShutting down...")
            sys.exit(0)
        except Exception as e:
            print(f"Unexpected error: {e}", file=sys.stderr)
            if args.once:
                sys.exit(1)
            time.sleep(args.interval)


if __name__ == '__main__':
    main()
