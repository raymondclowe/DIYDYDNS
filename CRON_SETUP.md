# DIY Dynamic DNS - Cron Setup Example

If you prefer to use cron instead of systemd, you can schedule the client to run periodically.

## Using Cron (Alternative to Systemd)

### For the client (runs every 5 minutes):

```bash
# Edit your crontab
crontab -e

# Add this line (adjust paths as needed):
*/5 * * * * /usr/bin/python3 /opt/diydydns/client.py --server user@your-server.com --remote-path /var/www/html/myip.txt --once >> /var/log/diydydns-client.log 2>&1
```

Note: The `--once` flag makes the client run once and exit, which is appropriate for cron.

### For the server:

You should still use systemd (or another init system) for the server, as it needs to run continuously. Alternatively, you can use a simple init script or run it in a screen/tmux session.

## Cron vs Systemd

### Use Cron when:
- You want simpler setup
- You're on a system without systemd
- You only want to check occasionally (e.g., every 5-10 minutes)

### Use Systemd when:
- You want automatic restarts on failure
- You want tighter integration with the system
- You want more control over service dependencies
- You want better logging integration

## Example: Full Cron Setup

```bash
# 1. Install the scripts
sudo mkdir -p /opt/diydydns
sudo cp client.py /opt/diydydns/
sudo chmod +x /opt/diydydns/client.py

# 2. Test it works
/opt/diydydns/client.py --server user@your-server.com --remote-path /var/www/html/myip.txt --once

# 3. Add to crontab (every 5 minutes)
echo "*/5 * * * * /usr/bin/python3 /opt/diydydns/client.py --server user@your-server.com --remote-path /var/www/html/myip.txt --once >> /tmp/diydydns.log 2>&1" | crontab -

# 4. Verify it's scheduled
crontab -l
```

## Logging

To see the logs from your cron job:

```bash
tail -f /tmp/diydydns.log
# or wherever you directed the output in your crontab entry
```
