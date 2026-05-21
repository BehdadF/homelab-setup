# Self-Hosting Services

A single `setup.sh` script that installs and manages self-hosted services on Ubuntu.
Tested on **Raspberry Pi 4/5 (Ubuntu 24.04 arm64)**; also works on any amd64 Ubuntu 22.04+ server.

Each service runs in its own Docker container with `restart: always`. A [Homer](https://github.com/bastienwirtz/homer) dashboard on port 80 lists every installed service. The script detects LAN IP changes automatically and reconfigures services via a lightweight systemd daemon.

---

## Quick Start

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/setup.sh -o setup.sh

# See what's available
bash setup.sh --list

# Install one or more services (installs Docker automatically if missing)
sudo bash setup.sh --vaultwarden --nextcloud

# Install everything
sudo bash setup.sh --all
```

After the first install, `setup.sh` is copied to `/opt/self-hosting/setup.sh` for subsequent use:
```bash
sudo bash /opt/self-hosting/setup.sh --immich
```

---

## Services

| Service | Port | Category | Description |
|---------|------|----------|-------------|
| Homer | 80 | System | Dashboard home page |
| Portainer | 9000 | System | Docker container management |
| **Vaultwarden** | 8200 (HTTPS) | Security | Bitwarden-compatible password vault |
| Joplin Server | 22300 | Productivity | Markdown note sync |
| Nextcloud | 8180 | Storage | Files, calendar, contacts |
| Paperless-ngx | 8010 | Productivity | Document management |
| Seafile | 8082 | Storage | Fast file sync & share |
| MinIO | 9001 / 9100 | Storage | S3-compatible object storage |
| **Immich** | 2283 | Media | Self-hosted Google Photos |
| Jellyfin | 8096 | Media | Media streaming server |
| Forgejo | 3000 | Dev | Self-hosted Git forge |
| code-server | 8443 | Dev | VS Code in the browser |
| Woodpecker CI | 8000 | Dev | Lightweight CI/CD |
| Pritunl | 8888 | Network | OpenVPN / WireGuard VPN |
| Headscale | 8085 | Network | Self-hosted Tailscale controller |
| Uptime Kuma | 3001 | Monitoring | Service uptime monitoring |
| Netdata | 19999 | Monitoring | Real-time system metrics |
| Prometheus | 9090 | Monitoring | Metrics collection |
| Grafana | 3100 | Monitoring | Metrics dashboards |

---

## HTTPS

Services marked **HTTPS** (Vaultwarden, Joplin) are proxied by [Caddy](https://caddyserver.com/) running as a host systemd service. Caddy uses its built-in local CA (`tls internal`) — no domain name or Let's Encrypt needed.

**Trust the root CA once per client device** (shown automatically after first install):

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /opt/self-hosting/data/caddy-root.crt

# Ubuntu / Debian
sudo cp /opt/self-hosting/data/caddy-root.crt /usr/local/share/ca-certificates/selfhosted.crt
sudo update-ca-certificates

# iOS / Android
# Copy caddy-root.crt to device → Settings → VPN & Device Management
```

To re-display the trust instructions:
```bash
sudo bash /opt/self-hosting/setup.sh --export-cert
```

---

## Common Operations

```bash
# See installed services with their URLs
sudo bash setup.sh --list-installed

# Restart a service
sudo bash setup.sh --restart vaultwarden
sudo bash setup.sh --restart all

# Remove a service (keeps data)
sudo bash setup.sh --uninstall seafile

# Remove a service AND delete its data (irreversible)
sudo bash setup.sh --uninstall seafile --purge

# Remove everything
sudo bash setup.sh --uninstall-all
sudo bash setup.sh --uninstall-all --purge   # also deletes all data
```

---

## Credentials

Credentials are generated randomly at install time and stored in each service's `.env`:

```bash
cat /opt/self-hosting/compose/vaultwarden/.env
cat /opt/self-hosting/compose/grafana/.env
# etc.
```

---

## IP Changes

The `self-hosting-ip-monitor` systemd service polls your LAN IP every 30 seconds.
If it changes, it automatically reconfigures all IP-aware services (Homer dashboard,
Vaultwarden, Joplin, Nextcloud, Seafile, Headscale, Woodpecker, Caddy).

```bash
# Check monitor status
systemctl status self-hosting-ip-monitor

# View IP change history
cat /opt/self-hosting/logs/ip-changes.log

# Trigger manually
sudo bash /opt/self-hosting/setup.sh --update-ip 192.168.1.100
```

---

## Post-Install Notes

### Woodpecker CI
Requires a Forgejo OAuth app before it's usable:
1. In Forgejo → Settings → Applications → OAuth2 Apps → Add Application
   - Name: `Woodpecker CI`
   - Redirect URI: `http://SERVER_IP:8000/authorize`
2. Copy the Client ID and Secret into `/opt/self-hosting/compose/woodpecker/.env`
3. `sudo bash /opt/self-hosting/setup.sh --restart woodpecker`

### Jellyfin
Add media to `/opt/self-hosting/data/jellyfin/media/` and configure libraries on first visit.

### Pritunl
Forward UDP port 1194 on your router to the server IP for VPN client access.
The one-time setup key is shown at install time; if missed:
```bash
docker logs pritunl | grep setup-key
```

### Headscale
```bash
# Create a user and generate a pre-auth key
docker exec headscale headscale users create myuser
docker exec headscale headscale preauthkeys create --user myuser --reusable

# On each Tailscale client
tailscale up --login-server http://SERVER_IP:8085
```

### MinIO
- Console UI: `http://SERVER_IP:9001`
- S3 API endpoint: `http://SERVER_IP:9100`

---

## File Layout

```
/opt/self-hosting/
├── setup.sh                  ← script installed here for stable path
├── .installed                ← list of installed service names
├── .current-ip               ← last known LAN IP
├── compose/<service>/
│   ├── docker-compose.yml
│   └── .env                  ← generated credentials (chmod 600)
├── config/<service>/         ← generated config files (prometheus.yml, etc.)
├── data/<service>/           ← persistent volumes (kept on --uninstall)
├── scripts/ip-monitor.sh     ← IP change polling daemon
└── logs/ip-changes.log       ← timestamped IP change history
```

---

## Requirements

- Ubuntu 22.04+ or Debian 12+ (amd64 or arm64)
- Run as root / sudo
- Internet access for image pulls
- Ports 80 and 443 available on the host

Docker and Docker Compose are installed automatically if not present.
