# homelab-setup

A single `setup.sh` that installs and manages self-hosted services on any Debian-based system (Ubuntu, Debian, Raspberry Pi OS, etc.) — amd64 or arm64.

Each service runs in Docker with `restart: always`. A [Homer](https://github.com/bastienwirtz/homer) dashboard on port 80 lists everything. LAN IP changes are detected automatically via a systemd polling daemon.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/behdadf/homelab-setup/main/setup.sh -o setup.sh
```

```bash
bash setup.sh --list
```

```bash
sudo bash setup.sh --vaultwarden --nextcloud
```

```bash
sudo bash setup.sh --all
```

After the first install, `setup.sh` is copied to `/opt/self-hosting/setup.sh`:

```bash
sudo bash /opt/self-hosting/setup.sh --immich
```

## Services

| Service | Port | Category | Description |
|---------|------|----------|-------------|
| Homer | 80 | System | Dashboard home page |
| Portainer | 9000 | System | Docker container management |
| Vaultwarden | 8200 (HTTPS) | Security | Bitwarden-compatible password vault |
| Joplin Server | 22300 | Productivity | Markdown note sync |
| Nextcloud | 8180 | Storage | Files, calendar, contacts |
| Paperless-ngx | 8010 | Productivity | Document management |
| Seafile | 8082 | Storage | Fast file sync & share |
| MinIO | 9001 / 9100 | Storage | S3-compatible object storage |
| Immich | 2283 | Media | Self-hosted Google Photos |
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
| FreshRSS | 8280 | Productivity | RSS feed aggregator |
| AdGuard Home | 8053 / 53 | Network | DNS ad blocker |
| Linkding | 8380 | Productivity | Bookmark manager |

## HTTPS

Vaultwarden is proxied by [Caddy](https://caddyserver.com/) running as a host systemd service with `tls internal` — no domain name or Let's Encrypt needed.

Trust the root CA once per client device (shown after first install):

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /opt/self-hosting/data/caddy-root.crt

# Ubuntu / Debian
sudo cp /opt/self-hosting/data/caddy-root.crt /usr/local/share/ca-certificates/selfhosted.crt
sudo update-ca-certificates

# iOS / Android — copy caddy-root.crt to device, install via Settings
```

Re-export the cert any time with `sudo bash /opt/self-hosting/setup.sh --export-cert`.

## Usage

```bash
sudo bash setup.sh --list-installed

sudo bash setup.sh --stop grafana
sudo bash setup.sh --stop all
sudo bash setup.sh --restart vaultwarden
sudo bash setup.sh --restart all

sudo bash setup.sh --uninstall seafile
sudo bash setup.sh --uninstall seafile --purge
sudo bash setup.sh --uninstall-all
sudo bash setup.sh --uninstall-all --purge
```

`--uninstall` removes containers but keeps data. `--purge` deletes data too (requires confirmation).

## Credentials

Generated at install time, stored in each service's `.env`:

```bash
cat /opt/self-hosting/compose/vaultwarden/.env
cat /opt/self-hosting/compose/grafana/.env
```

## IP Changes

The `self-hosting-ip-monitor` systemd service polls every 30 seconds. On change, it reconfigures Homer, Caddy, Vaultwarden, Joplin, Nextcloud, Seafile, Headscale, and Woodpecker.

```bash
systemctl status self-hosting-ip-monitor
cat /opt/self-hosting/logs/ip-changes.log
sudo bash /opt/self-hosting/setup.sh --update-ip 192.168.1.100
```

## Post-Install Notes

**Woodpecker CI** — needs a Forgejo OAuth app:
1. Forgejo → Settings → Applications → OAuth2 → Add
   - Name: `Woodpecker CI`, Redirect URI: `http://SERVER_IP:8000/authorize`
2. Put the Client ID and Secret in `/opt/self-hosting/compose/woodpecker/.env`
3. `sudo bash /opt/self-hosting/setup.sh --restart woodpecker`

**Jellyfin** — add media to `/opt/self-hosting/data/jellyfin/media/`, configure libraries on first visit.

**Pritunl** — forward UDP 1194 on your router. Setup key:
```bash
docker logs pritunl | grep setup-key
```

**Headscale** — no web UI, CLI only:
```bash
docker exec headscale headscale users create myuser
docker exec headscale headscale users list
docker exec headscale headscale preauthkeys create --user USER_ID
tailscale up --login-server http://SERVER_IP:8085 --authkey YOUR_KEY
```
Generate a new key per device. Add `--reusable` only if you need one key for multiple devices.

**MinIO** — console on `:9001`, S3 API on `:9100`.

**AdGuard Home** — during the setup wizard, set the web UI listen address to `0.0.0.0:3000` (not port 80, which Homer uses). The script maps it to `:8053` externally. After setup, point your router's DHCP DNS to the Pi's IP for network-wide ad blocking. The script disables `systemd-resolved`'s stub listener automatically if needed.

## File Layout

```
/opt/self-hosting/
├── setup.sh
├── .installed
├── .current-ip
├── compose/<service>/
│   ├── docker-compose.yml
│   └── .env
├── config/<service>/
├── data/<service>/
├── scripts/ip-monitor.sh
└── logs/ip-changes.log
```

## Requirements

- Ubuntu 22.04+ / Debian 12+ (or derivatives), amd64 or arm64
- Root access
- Internet for image pulls
- Port 80 available (443 if using HTTPS services)

Docker is installed automatically if missing.
