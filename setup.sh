#!/usr/bin/env bash
# setup.sh — homelab-setup
# https://github.com/behdadf/homelab-setup
# Ubuntu 22.04+ (amd64/arm64). Run with sudo.
set -euo pipefail
IFS=$'\n\t'

readonly VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/${SCRIPT_NAME}"
readonly INSTALL_DIR="/opt/self-hosting"
readonly COMPOSE_DIR="${INSTALL_DIR}/compose"
readonly CONFIG_DIR="${INSTALL_DIR}/config"
readonly DATA_DIR="${INSTALL_DIR}/data"
readonly SCRIPTS_DIR="${INSTALL_DIR}/scripts"
readonly LOGS_DIR="${INSTALL_DIR}/logs"
readonly INSTALLED_FILE="${INSTALL_DIR}/.installed"
readonly IP_FILE="${INSTALL_DIR}/.current-ip"

DC_CMD=""

if [[ -t 1 ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RESET='\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
    C_CYAN='' C_BOLD='' C_DIM='' C_RESET=''
fi

info()    { echo -e "${C_BLUE}[INFO]${C_RESET}  $*"; }
success() { echo -e "${C_GREEN}[ OK ]${C_RESET}  $*"; }
warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*"; }
error()   { echo -e "${C_RED}[ ERR]${C_RESET}  $*" >&2; }
die()     { error "$*"; exit 1; }
header()  { echo -e "\n${C_BOLD}${C_CYAN}══  $*  ══${C_RESET}"; }
dim()     { echo -e "${C_DIM}$*${C_RESET}"; }
blank()   { echo ""; }

# reg <name> <port> "<description>" <category> [ip_aware] [needs_https]
declare -a  SVC_NAMES
declare -A  SVC_PORT SVC_DESC SVC_CAT SVC_IP_AWARE SVC_NEEDS_HTTPS
declare -A  SVC_RAM_MB

reg() {
    local name="$1" port="$2" desc="$3" cat="$4" \
          ip_aware="${5:-false}" needs_https="${6:-false}"
    SVC_NAMES+=("$name")
    SVC_PORT["$name"]="$port"
    SVC_DESC["$name"]="$desc"
    SVC_CAT["$name"]="$cat"
    SVC_IP_AWARE["$name"]="$ip_aware"
    SVC_NEEDS_HTTPS["$name"]="$needs_https"
}

# ── System ───────────────────────────────────────────────────
reg dashboard    80     "Homer — service dashboard & home page"              system     true
reg portainer    9000   "Portainer CE — Docker container management UI"      system     false
reg caddy        443    "Caddy — HTTPS reverse proxy (auto-managed TLS)"     system     true

# ── Security ─────────────────────────────────────────────────
reg vaultwarden  8200   "Vaultwarden — Bitwarden-compatible password vault"  security   true  true

# ── Productivity ─────────────────────────────────────────────
reg joplin       22300  "Joplin Server — Markdown note sync"                 productivity true
reg paperless    8010   "Paperless-ngx — document management system"         productivity false

# ── Storage ──────────────────────────────────────────────────
reg nextcloud    8180   "Nextcloud — files, calendar, contacts"              storage    true
reg seafile      8082   "Seafile — fast file sync & share"                   storage    true
reg minio        9001   "MinIO — S3-compatible object storage (console)"     storage    false

# ── Media ────────────────────────────────────────────────────
reg immich       2283   "Immich — self-hosted Google Photos alternative"     media      false
reg jellyfin     8096   "Jellyfin — media streaming server"                  media      false
reg navidrome    4533   "Navidrome — music streaming server"                  media      false

# ── Networking / VPN ─────────────────────────────────────────
reg pritunl      8888   "Pritunl — OpenVPN / WireGuard VPN server"           network    true
reg headscale    8085   "Headscale — self-hosted Tailscale control server"   network    true

# ── Developer Tools ──────────────────────────────────────────
reg forgejo      3000   "Forgejo — self-hosted Git forge"                    dev        false
reg woodpecker   8000   "Woodpecker CI — lightweight CI/CD pipeline"         dev        true
reg codeserver   8443   "code-server — VS Code in the browser"               dev        false

# ── Monitoring ───────────────────────────────────────────────
reg uptimekuma   3001   "Uptime Kuma — service uptime monitoring"            monitoring false
reg netdata      19999  "Netdata — real-time system performance metrics"     monitoring false
reg prometheus   9090   "Prometheus — metrics collection & alerting"         monitoring false
reg grafana      3100   "Grafana — metrics visualization dashboards"         monitoring false
reg freshrss     8280   "FreshRSS — RSS feed aggregator"                     productivity false
reg adguard      8053   "AdGuard Home — network-wide DNS ad blocker"         network    false
reg linkding     8380   "Linkding — bookmark manager"                        productivity false
reg authentik    9443   "Authentik — SSO & identity provider"                security   false
reg ollama       8480   "Ollama + Open WebUI — local LLM chat"               dev        false

get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)          echo "amd64" ;;
        aarch64|arm64)   echo "arm64" ;;
        armv7l)          echo "armhf" ;;
        *)               echo "$arch" ;;
    esac
}

check_os() {
    header "Checking OS"

    [[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release not found."

    # grep+cut instead of sourcing — avoids readonly VERSION collision
    local os_id os_pretty os_version_id os_id_like
    os_id=$(         grep -m1 '^ID='            /etc/os-release | cut -d= -f2 | tr -d '"' || echo "")
    os_pretty=$(     grep -m1 '^PRETTY_NAME='   /etc/os-release | cut -d= -f2 | tr -d '"' || echo "unknown")
    os_version_id=$( grep -m1 '^VERSION_ID='    /etc/os-release | cut -d= -f2 | tr -d '"' || echo "0")
    os_id_like=$(    grep -m1 '^ID_LIKE='       /etc/os-release | cut -d= -f2 | tr -d '"' || echo "")

    local arch
    arch=$(get_arch)

    info "Distro  : ${os_pretty}"
    info "Arch    : ${arch}"
    info "Kernel  : $(uname -r)"

    case "${os_id}" in
        ubuntu|debian) ;;
        *)
            if [[ "${os_id_like}" != *ubuntu* && "${os_id_like}" != *debian* ]]; then
                die "Unsupported OS '${os_id:-unknown}'. This script requires Ubuntu 22.04+ or Debian 12+."
            fi
            ;;
    esac

    if [[ "${os_id}" == "ubuntu" ]]; then
        local ver_major
        ver_major=$(echo "${os_version_id}" | cut -d. -f1)
        (( ver_major >= 22 )) || \
            die "Ubuntu ${os_version_id} is too old. Please use 22.04 or later."
    fi

    case "$arch" in
        amd64|arm64) ;;
        *) warn "Architecture '${arch}' is untested. Some images may not be available." ;;
    esac

    success "OS check passed"
}

install_docker() {
    header "Docker"

    if docker info &>/dev/null 2>&1; then
        local version
        version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        success "Docker already installed (v${version}) — skipping"
        return 0
    fi

    info "Installing Docker from the official repository…"

    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    codename=$(grep -m1 '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo "")
    [[ -z "$codename" ]] && codename=$(lsb_release -cs 2>/dev/null || echo "noble")
    local arch
    arch=$(get_arch)

    echo \
        "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${codename} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "${SUDO_USER}"
        info "Added '${SUDO_USER}' to the docker group (re-login to take effect)"
    fi

    local version
    version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    success "Docker v${version} installed"
}

check_prerequisites() {
    header "Prerequisites"
    local failed=false

    if docker info &>/dev/null 2>&1; then
        success "Docker daemon is running"
    else
        error "Docker daemon is not running.  Try: sudo systemctl start docker"
        failed=true
    fi

    if docker compose version &>/dev/null 2>&1; then
        local cv
        cv=$(docker compose version --short 2>/dev/null || echo "unknown")
        success "docker compose v${cv} (plugin)"
    elif command -v docker-compose &>/dev/null; then
        success "docker-compose (standalone) found"
    else
        error "Docker Compose not found. Install docker-compose-plugin or docker-compose."
        failed=true
    fi

    if command -v openssl &>/dev/null; then
        success "openssl available"
    else
        error "openssl not found. Install with: sudo apt-get install -y openssl"
        failed=true
    fi

    if command -v curl &>/dev/null; then
        success "curl available"
    else
        error "curl not found. Install with: sudo apt-get install -y curl"
        failed=true
    fi

    local port80_pid
    port80_pid=$(ss -tlnp 'sport = :80' 2>/dev/null \
                    | awk 'NR>1 && /LISTEN/ {print $NF}' \
                    | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    if [[ -n "$port80_pid" ]]; then
        local port80_proc
        port80_proc=$(ps -p "$port80_pid" -o comm= 2>/dev/null || echo "unknown")
        if [[ "$port80_proc" != "docker"* ]]; then
            warn "Port 80 is in use by '${port80_proc}' (pid ${port80_pid})."
            warn "The dashboard container will fail to start unless port 80 is free."
        fi
    else
        success "Port 80 is free"
    fi

    $failed && die "One or more prerequisites are missing. Fix the errors above and re-run."
    success "All prerequisites satisfied"
}

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root.  Try: sudo $SCRIPT_NAME $*"
}

# Routing table lookup — no packet sent.
get_current_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null \
            | grep -oP 'src \K[\d.]+' \
            | head -1) \
        || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "${ip:-127.0.0.1}"
}

gen_password() { openssl rand -hex 16; }

# ── ZFS helpers (no-op when ZFS is not available) ────────────
HAS_ZFS=false
ZFS_DATA_DATASET=""

zfs_detect() {
    command -v zfs &>/dev/null || return 0
    local mnt
    mnt=$(df --output=source "${DATA_DIR}" 2>/dev/null | tail -1) || return 0
    if zfs list -H -o name "$mnt" &>/dev/null 2>&1; then
        HAS_ZFS=true
        ZFS_DATA_DATASET="$mnt"
        success "ZFS detected — dataset: ${ZFS_DATA_DATASET}"
    fi
}

zfs_snapshot() {
    $HAS_ZFS || return 0
    local tag="$1"
    local snap="${ZFS_DATA_DATASET}@${tag}"
    if zfs snapshot -r "$snap" 2>/dev/null; then
        success "ZFS snapshot: ${snap}"
    else
        warn "ZFS snapshot failed: ${snap}"
    fi
}

zfs_list_snapshots() {
    if ! $HAS_ZFS; then
        info "ZFS is not in use — no snapshots available."
        return 0
    fi
    header "ZFS Snapshots"
    blank
    zfs list -t snapshot -o name,creation,used -s creation -r "$ZFS_DATA_DATASET"
    blank
}

zfs_rollback() {
    if ! $HAS_ZFS; then
        die "ZFS is not in use — rollback is not available."
    fi
    local svc="$1"
    local dataset="${ZFS_DATA_DATASET}/${svc}"

    if ! zfs list -H -o name "$dataset" &>/dev/null 2>&1; then
        dataset="$ZFS_DATA_DATASET"
    fi

    local latest
    latest=$(zfs list -t snapshot -H -o name -s creation -r "$dataset" | tail -1)
    if [[ -z "$latest" ]]; then
        die "No snapshots found for ${dataset}."
    fi

    warn "This will roll back to: ${latest}"
    warn "All changes after this snapshot will be lost."
    printf "  Type 'yes' to confirm: "
    local confirm; read -r confirm
    [[ "$confirm" == "yes" ]] || { info "Rollback cancelled."; return 0; }

    local compose_dir="${COMPOSE_DIR}/${svc}"
    if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
        dc "$compose_dir" down 2>/dev/null || true
    fi

    if zfs rollback -r "$latest"; then
        success "Rolled back to ${latest}."
        if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
            dc "$compose_dir" up -d 2>/dev/null || true
            success "${svc} restarted."
        fi
    else
        error "Rollback failed. Check 'zfs list -t snapshot' for valid snapshots."
    fi
}

load_env_var() {
    local env_file="$1" key="$2"
    if [[ -f "$env_file" ]]; then
        grep "^${key}=" "$env_file" 2>/dev/null | head -1 | cut -d= -f2-
    fi
}

port_is_free() {
    ! ss -tln 2>/dev/null | awk 'NR>1{print $4}' | grep -qE ":${1}$"
}

check_disk() {
    local svc="$1"
    local free_mb
    free_mb=$(df -m "${DATA_DIR}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    if (( free_mb < 1024 )); then
        warn "${svc}: only ${free_mb}MB disk free on ${DATA_DIR}."
        printf "  Continue anyway? [y/N] "
        local answer; read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || { info "Skipping ${svc}."; return 1; }
    fi
}

check_runtime() {
    local svc="$1"
    local ram_mb cpu_count load_1m
    ram_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    cpu_count=$(nproc 2>/dev/null || echo 1)
    load_1m=$(awk '{printf "%d", $1}' /proc/loadavg 2>/dev/null || echo 0)

    local problems=()
    (( ram_mb < 512 )) && problems+=("${ram_mb}MB RAM free")
    (( load_1m >= cpu_count )) && problems+=("system load ${load_1m} (${cpu_count} cores)")

    if [[ ${#problems[@]} -gt 0 ]]; then
        local IFS=", "
        warn "${svc}: ${problems[*]}. It may run slowly or get killed."
        printf "  Start anyway? [y/N] "
        local answer; read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || { info "${svc} installed but not started. Use --restart ${svc} later."; return 1; }
    fi
}

require_port() {
    local port="$1" svc="${2:-service}"
    port_is_free "$port" \
        || die "Port ${port} is already in use — cannot start ${svc}.
Check what's using it with:  sudo ss -tlnp | grep :${port}
Then free the port and re-run:  sudo bash setup.sh --${svc}"
}

is_installed() {
    grep -qxF "$1" "${INSTALLED_FILE}" 2>/dev/null
}

mark_installed() {
    local name="$1"
    grep -qxF "$name" "${INSTALLED_FILE}" 2>/dev/null \
        || echo "$name" >> "${INSTALLED_FILE}"
}

mark_uninstalled() {
    local name="$1"
    [[ -f "${INSTALLED_FILE}" ]] || return 0
    local tmp
    tmp=$(mktemp)
    grep -vxF "$name" "${INSTALLED_FILE}" > "$tmp" || true
    mv "$tmp" "${INSTALLED_FILE}"
}

is_valid_service() {
    [[ -n "${SVC_PORT[$1]+x}" ]]
}

detect_docker_compose() {
    if docker compose version &>/dev/null 2>&1; then
        DC_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DC_CMD="docker-compose"
    else
        DC_CMD=""
    fi
}

dc() {
    [[ -n "$DC_CMD" ]] || die "Docker Compose not available. Run prerequisites first."
    local service_dir="$1"; shift

    if [[ "${1:-}" == "up" ]]; then
        local svc_name
        svc_name=$(basename "$service_dir")
        check_runtime "$svc_name" || return 1
    fi

    local -a cmd
    IFS=' ' read -ra cmd <<< "$DC_CMD"
    cmd+=(-f "${service_dir}/docker-compose.yml")
    [[ -f "${service_dir}/.env" ]] && cmd+=(--env-file "${service_dir}/.env")
    "${cmd[@]}" "$@"
}

init_dirs() {
    local -a dirs=(
        "${COMPOSE_DIR}"
        "${CONFIG_DIR}"
        "${DATA_DIR}"
        "${SCRIPTS_DIR}"
        "${LOGS_DIR}"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
    done
    touch "${INSTALLED_FILE}"
    success "Directories ready under ${INSTALL_DIR}"
}

list_services() {
    header "Available Services"
    blank

    local -A printed_cats
    for name in "${SVC_NAMES[@]}"; do
        local cat="${SVC_CAT[$name]}"
        if [[ -z "${printed_cats[$cat]+x}" ]]; then
            printed_cats["$cat"]=1
            echo -e "  ${C_BOLD}[${cat}]${C_RESET}"
            for svc in "${SVC_NAMES[@]}"; do
                [[ "${SVC_CAT[$svc]}" == "$cat" ]] || continue
                local marker=""
                is_installed "$svc" && marker=" ${C_GREEN}✓${C_RESET}"
                printf "    ${C_CYAN}--%-16s${C_RESET} port %-6s  %s%b\n" \
                    "$svc" "${SVC_PORT[$svc]}" "${SVC_DESC[$svc]}" "$marker"
            done
            blank
        fi
    done

    dim "  ${C_GREEN}✓${C_RESET}${C_DIM} = already installed   |   ports are LAN-only (bind to server IP)${C_RESET}"
    blank
}

list_installed() {
    header "Installed Services"
    blank

    local count=0
    local ip
    ip=$(get_current_ip)

    for name in "${SVC_NAMES[@]}"; do
        is_installed "$name" || continue
        printf "  ${C_GREEN}%-16s${C_RESET}  %-36s  %s\n" \
            "$name" "$(svc_url "$name" "$ip")" "${SVC_DESC[$name]}"
        (( count++ )) || true
    done

    if [[ $count -eq 0 ]]; then
        dim "  No services installed yet. Run --list to see available services."
    fi
    blank
}

print_usage() {
    cat <<EOF

${C_BOLD}Homelab Setup${C_RESET} v${VERSION}

${C_BOLD}Usage:${C_RESET}
  sudo $SCRIPT_NAME [OPTIONS] [SERVICES]

${C_BOLD}Install:${C_RESET}
  --all                     Install every available service
  --<service>               Install one service  (e.g. --vaultwarden)
                            Multiple flags are allowed: --nextcloud --immich

${C_BOLD}Uninstall:${C_RESET}
  --uninstall <service>     Stop and remove a service; data is kept
  --uninstall-all           Remove all installed services; data is kept
  --purge                   Modifier: also delete data during uninstall
  --purge <service|all>     Delete leftover data for already-uninstalled service(s)

${C_BOLD}Utilities:${C_RESET}
  --list                    Show all available services, ports, and categories
  --list-installed          Show installed services with their current URLs
  --stop <service|all>      Stop a service without removing it; use --restart to bring it back
  --restart <service|all>   Restart a service (or all installed services)
  --export-cert             Re-export Caddy's root CA and print trust instructions
  --upgrade <service|all>   Pull latest images, snapshot (if ZFS), and restart
  --update-ip <ip>          Reconfigure IP-aware services for a new LAN address
                            (Called automatically by the ip-monitor systemd service)
  --snapshots               List all ZFS snapshots (requires ZFS)
  --snapshot <service|all>  Take a ZFS snapshot now (requires ZFS)
  --rollback <service>      Roll back a service to its most recent ZFS snapshot
  --help, -h                Show this help

${C_BOLD}Examples:${C_RESET}
  sudo $SCRIPT_NAME --list
  sudo $SCRIPT_NAME --vaultwarden --nextcloud --immich
  sudo $SCRIPT_NAME --all
  sudo $SCRIPT_NAME --uninstall seafile
  sudo $SCRIPT_NAME --uninstall seafile --purge
  sudo $SCRIPT_NAME --uninstall-all --purge
  sudo $SCRIPT_NAME --purge joplin
  sudo $SCRIPT_NAME --purge all

${C_BOLD}File Layout:${C_RESET}
  ${INSTALL_DIR}/
    compose/<service>/      docker-compose.yml + .env (credentials)
    config/<service>/       static / generated config files
    data/<service>/         persistent data volumes
    scripts/ip-monitor.sh   IP change daemon (managed by systemd)
    .installed              list of installed service names
    .current-ip             last known LAN IP

${C_BOLD}Notes:${C_RESET}
  • All services use 'restart: always' and survive reboots automatically.
  • The ip-monitor systemd service detects LAN IP changes and reconfigures
    services that embed the server IP in their config.
  • Credentials are never printed after initial install; recover them with:
      cat ${COMPOSE_DIR}/<service>/.env

EOF
}

_cat_icon() {
    case "$1" in
        system)       echo "fas fa-cogs" ;;
        security)     echo "fas fa-shield-alt" ;;
        productivity) echo "fas fa-tasks" ;;
        storage)      echo "fas fa-hdd" ;;
        media)        echo "fas fa-photo-video" ;;
        network)      echo "fas fa-network-wired" ;;
        dev)          echo "fas fa-code" ;;
        monitoring)   echo "fas fa-chart-line" ;;
        *)            echo "fas fa-layer-group" ;;
    esac
}

_svc_icon() {
    case "$1" in
        portainer)   echo "fab fa-docker" ;;
        vaultwarden) echo "fas fa-lock" ;;
        joplin)      echo "fas fa-sticky-note" ;;
        paperless)   echo "fas fa-file-alt" ;;
        nextcloud)   echo "fas fa-cloud" ;;
        seafile)     echo "fas fa-sync-alt" ;;
        minio)       echo "fas fa-database" ;;
        immich)      echo "fas fa-images" ;;
        jellyfin)    echo "fas fa-play-circle" ;;
        navidrome)   echo "fas fa-music" ;;
        pritunl)     echo "fas fa-user-shield" ;;
        headscale)   echo "fas fa-project-diagram" ;;
        forgejo)     echo "fas fa-code-branch" ;;
        woodpecker)  echo "fas fa-tools" ;;
        codeserver)  echo "fas fa-laptop-code" ;;
        uptimekuma)  echo "fas fa-heartbeat" ;;
        netdata)     echo "fas fa-tachometer-alt" ;;
        prometheus)  echo "fas fa-fire" ;;
        grafana)     echo "fas fa-chart-bar" ;;
        *)           echo "fas fa-cube" ;;
    esac
}

svc_url() {
    local name="$1" ip="$2"
    local scheme="http"
    [[ "${SVC_NEEDS_HTTPS[$name]:-false}" == "true" ]] && scheme="https"
    [[ "$name" == "pritunl" || "$name" == "authentik" ]] && scheme="https"
    echo "${scheme}://${ip}:${SVC_PORT[$name]}"
}

generate_homer_config() {
    local ip="$1"
    local config_file="${CONFIG_DIR}/homer/config.yml"
    mkdir -p "$(dirname "$config_file")"

    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "homeserver")

    cat > "$config_file" << EOF
---
# Generated by setup.sh — do not edit manually.
# Regenerated automatically on IP change or new service install.

title: "Home Server"
subtitle: "${hostname}"
icon: "fas fa-server"
header: true
footer: false
columns: 3
connectivityCheck: false

services:
EOF

    local -A printed_cats
    local has_services=false

    for name in "${SVC_NAMES[@]}"; do
        [[ "$name" == "dashboard" || "$name" == "caddy" || "$name" == "headscale" ]] && continue
        is_installed "$name"         || continue

        has_services=true
        local cat="${SVC_CAT[$name]}"

        if [[ -z "${printed_cats[$cat]+x}" ]]; then
            printed_cats["$cat"]=1
            printf '  - name: "%s"\n'  "${cat^}"          >> "$config_file"
            printf '    icon: "%s"\n'  "$(_cat_icon "$cat")" >> "$config_file"
            printf '    items:\n'                          >> "$config_file"
        fi

        printf '      - name: "%s"\n'        "$name"                         >> "$config_file"
        printf '        icon: "%s"\n'        "$(_svc_icon "$name")"           >> "$config_file"
        printf '        subtitle: "%s"\n'    "${SVC_DESC[$name]}"             >> "$config_file"
        printf '        url: "%s"\n'             "$(svc_url "$name" "$ip")"   >> "$config_file"
        printf '        target: "_blank"\n'                                   >> "$config_file"
    done

    if ! $has_services; then
        cat >> "$config_file" << 'EOF'
  - name: "Getting Started"
    icon: "fas fa-rocket"
    items:
      - name: "Install your first service"
        icon: "fas fa-terminal"
        subtitle: "Run: sudo setup.sh --list"
        url: "#"
        target: "_self"
EOF
    fi

    chmod 644 "$config_file"
    chmod 755 "$(dirname "$config_file")"

    success "Homer config → ${config_file}"
}

update_dashboard() {
    is_installed dashboard || return 0
    local ip
    ip=$(cat "${IP_FILE}" 2>/dev/null || get_current_ip)
    generate_homer_config "$ip"
    docker restart homer &>/dev/null || true
}

setup_dashboard() {
    local ip
    ip=$(get_current_ip)

    mkdir -p "${COMPOSE_DIR}/dashboard" "${CONFIG_DIR}/homer"

    generate_homer_config "$ip"

    cat > "${COMPOSE_DIR}/dashboard/docker-compose.yml" << EOF
services:
  homer:
    image: ghcr.io/bastienwirtz/homer:latest
    container_name: homer
    restart: always
    ports:
      - "80:8080"
    volumes:
      - ${CONFIG_DIR}/homer/config.yml:/www/assets/config.yml:ro
EOF

    require_port 80 dashboard
    info "Starting Homer dashboard…"
    dc "${COMPOSE_DIR}/dashboard" up -d
    mark_installed dashboard
    success "Dashboard → http://${ip}"
}

setup_portainer() {
    local ip
    ip=$(get_current_ip)

    mkdir -p "${COMPOSE_DIR}/portainer" "${DATA_DIR}/portainer"

    cat > "${COMPOSE_DIR}/portainer/docker-compose.yml" << EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DATA_DIR}/portainer:/data
EOF

    require_port "${SVC_PORT[portainer]}" portainer
    info "Starting Portainer…"
    dc "${COMPOSE_DIR}/portainer" up -d
    mark_installed portainer
    update_dashboard
    success "Portainer → http://${ip}:9000"
}

# Caddy runs on the host (apt/systemd), not Docker.
# HTTPS services bind 127.0.0.1:(port+10000), Caddy proxies with tls internal.
proxy_port_for() {
    echo $(( ${SVC_PORT[$1]} + 10000 ))
}

generate_caddyfile() {
    local ip="$1"
    : > /etc/caddy/Caddyfile

    # disable_redirects: don't bind port 80 (Homer owns it)
    cat >> /etc/caddy/Caddyfile << 'EOF'
{
    auto_https disable_redirects
}

EOF

    for name in "${SVC_NAMES[@]}"; do
        is_installed "$name"                                || continue
        [[ "${SVC_NEEDS_HTTPS[$name]:-false}" == "true" ]] || continue

        local pub_port; pub_port="${SVC_PORT[$name]}"
        local prx_port; prx_port="$(proxy_port_for "$name")"

        cat >> /etc/caddy/Caddyfile << EOF
${ip}:${pub_port} {
    tls internal
    reverse_proxy localhost:${prx_port}
}

EOF
    done

    success "Caddyfile written (/etc/caddy/Caddyfile)"
}

setup_caddy() {
    local ip; ip=$(get_current_ip)

    info "Installing Caddy from official apt repository…"
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y caddy

    systemctl enable caddy
    systemctl stop caddy 2>/dev/null || true

    mark_installed caddy
    success "Caddy installed and enabled — will start when first HTTPS service is configured"
}

update_caddy() {
    is_installed caddy || return 0
    local ip; ip=$(cat "${IP_FILE}" 2>/dev/null || get_current_ip)
    generate_caddyfile "$ip"
    systemctl reload-or-restart caddy
    sleep 3
    export_caddy_cert
}

export_caddy_cert() {
    local caddy_pki="/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt"
    local cert_dst="${DATA_DIR}/caddy-root.crt"
    local attempts=0

    until [[ -f "$caddy_pki" ]] || (( attempts++ >= 15 )); do
        sleep 2
    done

    if [[ -f "$caddy_pki" ]]; then
        local first_export=false
        [[ ! -f "$cert_dst" ]] && first_export=true
        cp "$caddy_pki" "$cert_dst"
        chmod 644 "$cert_dst"
        success "Caddy root CA → ${cert_dst}"
        if $first_export; then
            warn  "Trust this cert once on every device that accesses HTTPS services:"
            info  "  macOS      : sudo security add-trusted-cert -d -r trustRoot \\"
            info  "                 -k /Library/Keychains/System.keychain '${cert_dst}'"
            info  "  Ubuntu     : sudo cp '${cert_dst}' /usr/local/share/ca-certificates/selfhosted.crt && sudo update-ca-certificates"
            info  "  iOS/Android: copy ${cert_dst} to device → Settings → VPN & Device Management"
        fi
    else
        warn "Caddy root CA not yet generated — visit any https:// service to trigger it."
        warn "Then run:  sudo bash setup.sh --export-cert"
    fi
}

setup_vaultwarden() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/vaultwarden" "${DATA_DIR}/vaultwarden"

    local _env="${COMPOSE_DIR}/vaultwarden/.env"
    local admin_token; admin_token=$(load_env_var "$_env" ADMIN_TOKEN)
    admin_token=${admin_token:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Vaultwarden credentials."

    local proxy_port; proxy_port=$(proxy_port_for vaultwarden)

    cat > "${COMPOSE_DIR}/vaultwarden/.env" << EOF
ADMIN_TOKEN=${admin_token}
EOF
    chmod 600 "${COMPOSE_DIR}/vaultwarden/.env"

    cat > "${COMPOSE_DIR}/vaultwarden/docker-compose.yml" << EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    ports:
      - "127.0.0.1:${proxy_port}:80"
    volumes:
      - ${DATA_DIR}/vaultwarden:/data
    environment:
      - DOMAIN=https://${ip}:8200
      - ADMIN_TOKEN=\${ADMIN_TOKEN}
      - SIGNUPS_ALLOWED=true
      - WEBSOCKET_ENABLED=true
EOF

    require_port "$(proxy_port_for vaultwarden)" vaultwarden
    info "Starting Vaultwarden…"
    dc "${COMPOSE_DIR}/vaultwarden" up -d

    mark_installed vaultwarden
    update_caddy      # adds vaultwarden entry to Caddyfile, opens port 8200
    update_dashboard
    success "Vaultwarden  → https://${ip}:8200"
    info  "Admin panel  → https://${ip}:8200/admin"
    info  "Admin token  → ${COMPOSE_DIR}/vaultwarden/.env"
}

setup_joplin() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/joplin" \
             "${DATA_DIR}/joplin/db"

    local _env="${COMPOSE_DIR}/joplin/.env"
    local db_pass; db_pass=$(load_env_var "$_env" JOPLIN_DB_PASSWORD)
    db_pass=${db_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Joplin credentials."

    cat > "${COMPOSE_DIR}/joplin/.env" << EOF
JOPLIN_DB_PASSWORD=${db_pass}
EOF
    chmod 600 "${COMPOSE_DIR}/joplin/.env"

    cat > "${COMPOSE_DIR}/joplin/docker-compose.yml" << EOF
services:
  joplin:
    image: joplin/server:latest
    container_name: joplin
    restart: always
    ports:
      - "22300:22300"
    environment:
      - APP_PORT=22300
      - APP_BASE_URL=http://${ip}:22300
      - DB_CLIENT=pg
      - POSTGRES_HOST=joplin-db
      - POSTGRES_PORT=5432
      - POSTGRES_DATABASE=joplin
      - POSTGRES_USER=joplin
      - POSTGRES_PASSWORD=\${JOPLIN_DB_PASSWORD}
    depends_on:
      - joplin-db

  joplin-db:
    image: postgres:15-alpine
    container_name: joplin-db
    restart: always
    environment:
      - POSTGRES_DB=joplin
      - POSTGRES_USER=joplin
      - POSTGRES_PASSWORD=\${JOPLIN_DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/joplin/db:/var/lib/postgresql/data
EOF

    require_port "${SVC_PORT[joplin]}" joplin
    info "Starting Joplin Server…"
    dc "${COMPOSE_DIR}/joplin" up -d
    mark_installed joplin
    update_dashboard
    success "Joplin Server → http://${ip}:22300"
    info  "First login   → http://${ip}:22300 (create account on first visit)"
}

setup_nextcloud() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/nextcloud" \
             "${DATA_DIR}/nextcloud/html" \
             "${DATA_DIR}/nextcloud/db"

    local _env="${COMPOSE_DIR}/nextcloud/.env"
    local db_pass; db_pass=$(load_env_var "$_env" NC_DB_PASSWORD)
    local db_root; db_root=$(load_env_var "$_env" NC_DB_ROOT_PASSWORD)
    local admin_pass; admin_pass=$(load_env_var "$_env" NC_ADMIN_PASSWORD)
    db_pass=${db_pass:-$(gen_password)}
    db_root=${db_root:-$(gen_password)}
    admin_pass=${admin_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Nextcloud credentials."

    cat > "${COMPOSE_DIR}/nextcloud/.env" << EOF
NC_DB_PASSWORD=${db_pass}
NC_DB_ROOT_PASSWORD=${db_root}
NC_ADMIN_PASSWORD=${admin_pass}
EOF
    chmod 600 "${COMPOSE_DIR}/nextcloud/.env"

    local port="${SVC_PORT[nextcloud]}"
    require_port "$port" nextcloud

    cat > "${COMPOSE_DIR}/nextcloud/docker-compose.yml" << EOF
services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: always
    ports:
      - "${port}:80"
    volumes:
      - ${DATA_DIR}/nextcloud/html:/var/www/html
    environment:
      - MYSQL_HOST=nextcloud-db
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=\${NC_DB_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${ip} localhost 127.0.0.1
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=\${NC_ADMIN_PASSWORD}
      - REDIS_HOST=nextcloud-redis
    depends_on:
      - nextcloud-db
      - nextcloud-redis

  nextcloud-db:
    image: mariadb:10.11
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    environment:
      - MYSQL_ROOT_PASSWORD=\${NC_DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=\${NC_DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/nextcloud/db:/var/lib/mysql

  nextcloud-redis:
    image: redis:7-alpine
    container_name: nextcloud-redis
    restart: always
EOF

    info "Starting Nextcloud…"
    dc "${COMPOSE_DIR}/nextcloud" up -d
    mark_installed nextcloud
    update_dashboard
    success "Nextcloud    → http://${ip}:${port}"
    info  "Login        → admin / (see ${COMPOSE_DIR}/nextcloud/.env)"
    warn  "First startup takes 1–2 minutes while Nextcloud initialises the DB."
}

setup_paperless() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/paperless" \
             "${DATA_DIR}/paperless/"{data,media,export,consume,db}

    local _env="${COMPOSE_DIR}/paperless/.env"
    local db_pass; db_pass=$(load_env_var "$_env" PAPERLESS_DB_PASSWORD)
    local secret;  secret=$(load_env_var "$_env" PAPERLESS_SECRET_KEY)
    db_pass=${db_pass:-$(gen_password)}
    secret=${secret:-$(gen_password)$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Paperless credentials."

    local tz
    tz=$(cat /etc/timezone 2>/dev/null \
         || timedatectl show --property=Timezone --value 2>/dev/null \
         || echo "UTC")

    cat > "${COMPOSE_DIR}/paperless/.env" << EOF
PAPERLESS_DB_PASSWORD=${db_pass}
PAPERLESS_SECRET_KEY=${secret}
EOF
    chmod 600 "${COMPOSE_DIR}/paperless/.env"

    cat > "${COMPOSE_DIR}/paperless/docker-compose.yml" << EOF
services:
  paperless:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: paperless
    restart: always
    ports:
      - "8010:8000"
    volumes:
      - ${DATA_DIR}/paperless/data:/usr/src/paperless/data
      - ${DATA_DIR}/paperless/media:/usr/src/paperless/media
      - ${DATA_DIR}/paperless/export:/usr/src/paperless/export
      - ${DATA_DIR}/paperless/consume:/usr/src/paperless/consume
    environment:
      - PAPERLESS_REDIS=redis://paperless-redis:6379
      - PAPERLESS_DBHOST=paperless-db
      - PAPERLESS_DBNAME=paperless
      - PAPERLESS_DBUSER=paperless
      - PAPERLESS_DBPASS=\${PAPERLESS_DB_PASSWORD}
      - PAPERLESS_SECRET_KEY=\${PAPERLESS_SECRET_KEY}
      - PAPERLESS_TIME_ZONE=${tz}
      - PAPERLESS_OCR_LANGUAGE=eng
      - PAPERLESS_TIKA_ENABLED=1
      - PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://paperless-gotenberg:3000
      - PAPERLESS_TIKA_ENDPOINT=http://paperless-tika:9998
    depends_on:
      - paperless-db
      - paperless-redis
      - paperless-gotenberg
      - paperless-tika

  paperless-db:
    image: docker.io/library/postgres:16-alpine
    container_name: paperless-db
    restart: always
    environment:
      - POSTGRES_DB=paperless
      - POSTGRES_USER=paperless
      - POSTGRES_PASSWORD=\${PAPERLESS_DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/paperless/db:/var/lib/postgresql/data

  paperless-redis:
    image: docker.io/library/redis:8-alpine
    container_name: paperless-redis
    restart: always

  paperless-gotenberg:
    image: docker.io/gotenberg/gotenberg:8
    container_name: paperless-gotenberg
    restart: always
    command:
      - "gotenberg"
      - "--chromium-disable-javascript=true"
      - "--chromium-allow-list=file:///tmp/.*"

  paperless-tika:
    image: docker.io/apache/tika:latest
    container_name: paperless-tika
    restart: always

EOF

    require_port "${SVC_PORT[paperless]}" paperless
    info "Starting Paperless-ngx…"
    dc "${COMPOSE_DIR}/paperless" up -d
    mark_installed paperless
    update_dashboard
    success "Paperless-ngx → http://${ip}:8010"
    info  "First login   → http://${ip}:8010 (create superuser on first visit)"
    warn  "Drop documents into ${DATA_DIR}/paperless/consume/ for auto-import."
}
setup_seafile() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/seafile" \
             "${DATA_DIR}/seafile/data" \
             "${DATA_DIR}/seafile/db"

    local _env="${COMPOSE_DIR}/seafile/.env"
    local db_root; db_root=$(load_env_var "$_env" SEAFILE_DB_ROOT)
    local jwt_key; jwt_key=$(load_env_var "$_env" SEAFILE_JWT_KEY)
    local admin_pass; admin_pass=$(load_env_var "$_env" SEAFILE_ADMIN_PASSWORD)
    db_root=${db_root:-$(gen_password)}
    jwt_key=${jwt_key:-$(gen_password)$(gen_password)}
    admin_pass=${admin_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Seafile credentials."

    cat > "${COMPOSE_DIR}/seafile/.env" << EOF
SEAFILE_DB_ROOT=${db_root}
SEAFILE_JWT_KEY=${jwt_key}
SEAFILE_ADMIN_PASSWORD=${admin_pass}
EOF
    chmod 600 "${COMPOSE_DIR}/seafile/.env"

    local port="${SVC_PORT[seafile]}"

    cat > "${COMPOSE_DIR}/seafile/docker-compose.yml" << EOF
services:
  seafile:
    image: seafileltd/seafile-mc:13.0-latest
    container_name: seafile
    restart: always
    ports:
      - "${port}:80"
    volumes:
      - ${DATA_DIR}/seafile/data:/shared
    environment:
      - DB_HOST=seafile-db
      - DB_ROOT_PASSWD=\${SEAFILE_DB_ROOT}
      - SEAFILE_ADMIN_EMAIL=admin@seafile.local
      - SEAFILE_ADMIN_PASSWORD=\${SEAFILE_ADMIN_PASSWORD}
      - SEAFILE_SERVER_HOSTNAME=${ip}:${port}
      - SEAFILE_SERVER_LETSENCRYPT=false
      - JWT_PRIVATE_KEY=\${SEAFILE_JWT_KEY}
      - TIME_ZONE=UTC
    depends_on:
      seafile-db:
        condition: service_healthy
      seafile-memcached:
        condition: service_started

  seafile-db:
    image: mariadb:10.11
    container_name: seafile-db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=\${SEAFILE_DB_ROOT}
      - MYSQL_LOG_BIN=1
      - MYSQL_ROOT_HOST=%
    volumes:
      - ${DATA_DIR}/seafile/db:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5

  seafile-memcached:
    image: memcached:1.6
    container_name: seafile-memcached
    restart: always
    entrypoint: memcached -m 256
EOF

    require_port "$port" seafile
    info "Starting Seafile…"
    dc "${COMPOSE_DIR}/seafile" up -d
    mark_installed seafile
    update_dashboard
    success "Seafile        → http://${ip}:${port}"
    info  "Login          → admin@seafile.local / (see ${COMPOSE_DIR}/seafile/.env)"
    warn  "First startup may take 1–2 minutes while Seafile initialises the DB."
}

setup_minio() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/minio" "${DATA_DIR}/minio"

    local root_user; root_user="admin"
    local _env="${COMPOSE_DIR}/minio/.env"
    local root_password; root_password=$(load_env_var "$_env" MINIO_ROOT_PASSWORD)
    root_password=${root_password:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing MinIO credentials."

    local console_port="${SVC_PORT[minio]}"   # 9001 — console UI
    local api_port=9100                        # S3-compatible API

    cat > "${COMPOSE_DIR}/minio/.env" << EOF
MINIO_ROOT_USER=${root_user}
MINIO_ROOT_PASSWORD=${root_password}
EOF
    chmod 600 "${COMPOSE_DIR}/minio/.env"

    cat > "${COMPOSE_DIR}/minio/docker-compose.yml" << EOF
services:
  minio:
    image: quay.io/minio/minio:latest
    container_name: minio
    restart: always
    command: server /data --console-address ":9001"
    ports:
      - "${api_port}:9000"
      - "${console_port}:9001"
    volumes:
      - ${DATA_DIR}/minio:/data
    environment:
      - MINIO_ROOT_USER=\${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=\${MINIO_ROOT_PASSWORD}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    require_port "$api_port" minio
    require_port "$console_port" minio
    info "Starting MinIO…"
    dc "${COMPOSE_DIR}/minio" up -d
    mark_installed minio
    update_dashboard
    success "MinIO Console  → http://${ip}:${console_port}"
    success "MinIO S3 API   → http://${ip}:${api_port}"
    info  "Login          → ${root_user} / (see ${COMPOSE_DIR}/minio/.env)"
}

setup_immich() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/immich" \
             "${DATA_DIR}/immich/upload" \
             "${DATA_DIR}/immich/db" \
             "${DATA_DIR}/immich/ml-cache"

    local _env="${COMPOSE_DIR}/immich/.env"
    local db_pass; db_pass=$(load_env_var "$_env" DB_PASSWORD)
    db_pass=${db_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Immich credentials."

    cat > "${COMPOSE_DIR}/immich/.env" << EOF
DB_PASSWORD=${db_pass}
DB_USERNAME=immich
DB_DATABASE_NAME=immich
UPLOAD_LOCATION=${DATA_DIR}/immich/upload
DB_DATA_LOCATION=${DATA_DIR}/immich/db
IMMICH_VERSION=release
EOF
    chmod 600 "${COMPOSE_DIR}/immich/.env"

    local port="${SVC_PORT[immich]}"

    cat > "${COMPOSE_DIR}/immich/docker-compose.yml" << 'COMPOSE'
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    container_name: immich-server
    restart: always
    ports:
      - "${IMMICH_PORT:-2283}:2283"
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    environment:
      - DB_HOSTNAME=immich-db
      - DB_USERNAME=${DB_USERNAME}
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_DATABASE_NAME=${DB_DATABASE_NAME}
      - REDIS_HOSTNAME=immich-redis
    depends_on:
      - immich-redis
      - immich-db
    healthcheck:
      disable: false

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    container_name: immich-machine-learning
    restart: always
    volumes:
      - ${DATA_DIR:-/opt/self-hosting/data}/immich/ml-cache:/cache
    healthcheck:
      disable: false

  immich-redis:
    image: docker.io/valkey/valkey:8-bookworm
    container_name: immich-redis
    restart: always
    healthcheck:
      test: redis-cli ping
      interval: 10s
      timeout: 5s
      retries: 5

  immich-db:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    container_name: immich-db
    restart: always
    environment:
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_USER=${DB_USERNAME}
      - POSTGRES_DB=${DB_DATABASE_NAME}
      - POSTGRES_INITDB_ARGS=--data-checksums
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
COMPOSE

    sed -i "s|\${IMMICH_PORT:-2283}|${port}|g" "${COMPOSE_DIR}/immich/docker-compose.yml"
    sed -i "s|\${DATA_DIR:-/opt/self-hosting/data}|${DATA_DIR}|g" "${COMPOSE_DIR}/immich/docker-compose.yml"

    require_port "$port" immich
    info "Starting Immich…"
    dc "${COMPOSE_DIR}/immich" up -d
    mark_installed immich
    update_dashboard
    success "Immich         → http://${ip}:${port}"
    info  "Create your admin account on first visit."
    warn  "Machine learning model download occurs on first face-detection run (~1 GB)."
}

setup_jellyfin() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/jellyfin" \
             "${DATA_DIR}/jellyfin/config" \
             "${DATA_DIR}/jellyfin/cache" \
             "${DATA_DIR}/jellyfin/media"

    local port="${SVC_PORT[jellyfin]}"

    cat > "${COMPOSE_DIR}/jellyfin/docker-compose.yml" << EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: always
    network_mode: host
    volumes:
      - ${DATA_DIR}/jellyfin/config:/config
      - ${DATA_DIR}/jellyfin/cache:/cache
      - ${DATA_DIR}/jellyfin/media:/media
    environment:
      - JELLYFIN_PublishedServerUrl=http://${ip}:${port}
EOF
    require_port "$port" jellyfin
    info "Starting Jellyfin…"
    dc "${COMPOSE_DIR}/jellyfin" up -d
    mark_installed jellyfin
    update_dashboard
    success "Jellyfin       → http://${ip}:${port}"
    info  "Add media to ${DATA_DIR}/jellyfin/media/ and configure libraries on first visit."
}

setup_navidrome() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/navidrome" \
             "${DATA_DIR}/navidrome/data" \
             "${DATA_DIR}/navidrome/music"

    local port="${SVC_PORT[navidrome]}"

    cat > "${COMPOSE_DIR}/navidrome/docker-compose.yml" << EOF
services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: always
    ports:
      - "${port}:4533"
    volumes:
      - ${DATA_DIR}/navidrome/data:/data
      - ${DATA_DIR}/navidrome/music:/music:ro
    environment:
      ND_SCANSCHEDULE: 1h
      ND_LOGLEVEL: info
      ND_BASEURL: ""
EOF

    require_port "$port" navidrome
    info "Starting Navidrome…"
    dc "${COMPOSE_DIR}/navidrome" up -d
    mark_installed navidrome
    update_dashboard
    success "Navidrome      → http://${ip}:${port}"
    info  "Create your admin account on first visit."
    info  "Add music to ${DATA_DIR}/navidrome/music/ — scans automatically every hour."
}

setup_forgejo() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/forgejo" "${DATA_DIR}/forgejo"

    local port="${SVC_PORT[forgejo]}"      # 3000 — web UI
    local ssh_port=2222                    # host SSH port (container 22)

    cat > "${COMPOSE_DIR}/forgejo/docker-compose.yml" << EOF
services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:latest
    container_name: forgejo
    restart: always
    ports:
      - "${port}:3000"
      - "${ssh_port}:22"
    volumes:
      - ${DATA_DIR}/forgejo:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      - USER_UID=1000
      - USER_GID=1000
EOF

    require_port "$port" forgejo
    require_port "$ssh_port" forgejo
    info "Starting Forgejo…"
    dc "${COMPOSE_DIR}/forgejo" up -d
    mark_installed forgejo
    update_dashboard
    success "Forgejo        → http://${ip}:${port}"
    info  "Complete the setup wizard on first visit."
    info  "Git SSH clone   → ssh://git@${ip}:${ssh_port}"
}

setup_codeserver() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/codeserver" \
             "${DATA_DIR}/codeserver/config"

    local _env="${COMPOSE_DIR}/codeserver/.env"
    local password; password=$(load_env_var "$_env" CODESERVER_PASSWORD)
    local sudo_password; sudo_password=$(load_env_var "$_env" CODESERVER_SUDO_PASSWORD)
    password=${password:-$(gen_password)}
    sudo_password=${sudo_password:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing code-server credentials."

    local tz
    tz=$(cat /etc/timezone 2>/dev/null \
         || timedatectl show --property=Timezone --value 2>/dev/null \
         || echo "UTC")

    cat > "${COMPOSE_DIR}/codeserver/.env" << EOF
CODESERVER_PASSWORD=${password}
CODESERVER_SUDO_PASSWORD=${sudo_password}
EOF
    chmod 600 "${COMPOSE_DIR}/codeserver/.env"

    local port="${SVC_PORT[codeserver]}"

    cat > "${COMPOSE_DIR}/codeserver/docker-compose.yml" << EOF
services:
  codeserver:
    image: lscr.io/linuxserver/code-server:latest
    container_name: codeserver
    restart: always
    ports:
      - "${port}:8443"
    volumes:
      - ${DATA_DIR}/codeserver/config:/config
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${tz}
      - PASSWORD=\${CODESERVER_PASSWORD}
      - SUDO_PASSWORD=\${CODESERVER_SUDO_PASSWORD}
EOF

    require_port "$port" codeserver
    info "Starting code-server…"
    dc "${COMPOSE_DIR}/codeserver" up -d
    mark_installed codeserver
    update_dashboard
    success "code-server    → http://${ip}:${port}"
    info  "Password       → (see ${COMPOSE_DIR}/codeserver/.env)"
}

setup_pritunl() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/pritunl" \
             "${DATA_DIR}/pritunl/db" \
             "${DATA_DIR}/pritunl/logs"

    local port="${SVC_PORT[pritunl]}"

    cat > "${COMPOSE_DIR}/pritunl/docker-compose.yml" << EOF
services:
  pritunl:
    image: jippi/pritunl:latest
    container_name: pritunl
    restart: always
    privileged: true
    network_mode: host
    volumes:
      - /lib/modules:/lib/modules:ro
      - ${DATA_DIR}/pritunl/logs:/var/log/pritunl
    environment:
      - PRITUNL_MONGODB_URI=mongodb://localhost:27017/pritunl
    depends_on:
      - pritunl-mongo

  pritunl-mongo:
    image: mongo:6
    container_name: pritunl-mongo
    restart: always
    ports:
      - "127.0.0.1:27017:27017"
    volumes:
      - ${DATA_DIR}/pritunl/db:/data/db
    command: mongod --quiet
EOF

    require_port "$port" pritunl
    require_port 27017 pritunl
    info "Starting Pritunl VPN…"
    dc "${COMPOSE_DIR}/pritunl" up -d
    mark_installed pritunl

    info "Configuring Pritunl web UI on port ${port}…"
    local attempts=0
    until docker exec pritunl-mongo mongosh --quiet --eval \
        "db.settings.updateOne({_id:\"app\"},{\$set:{server_port:${port},redirect_server:false}})" \
        localhost:27017/pritunl 2>/dev/null | grep -q '"modifiedCount": 1\|"matchedCount": 1' \
        || (( attempts++ >= 30 )); do
        sleep 2
    done

    if (( attempts < 30 )); then
        docker restart pritunl &>/dev/null
        sleep 3
        success "Pritunl web UI bound to port ${port}."
    else
        warn "Could not configure Pritunl port. Web UI may be on https://${ip}:443 instead."
    fi

    update_dashboard

    local setup_key=""
    setup_key=$(docker logs pritunl 2>/dev/null \
        | grep -oP 'setup-key: \K[a-f0-9]+' | tail -1 || true)

    success "Pritunl VPN    → https://${ip}:${port}"
    if [[ -n "$setup_key" ]]; then
        info  "Setup key      → ${setup_key}"
    else
        warn  "Setup key not yet available — run:  docker logs pritunl | grep setup-key"
    fi
    info  "Initial credentials: admin / admin  (change immediately after login)"
    warn  "Accept the self-signed certificate warning in your browser."
    warn  "Port-forward UDP 1194 on your router to ${ip} for VPN client access."
}

setup_headscale() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/headscale" \
             "${CONFIG_DIR}/headscale" \
             "${DATA_DIR}/headscale"

    local port="${SVC_PORT[headscale]}"

    cat > "${CONFIG_DIR}/headscale/config.yaml" << EOF
---
server_url: http://${ip}:${port}
listen_addr: 0.0.0.0:${port}
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: true
metrics_listen_addr: 127.0.0.1:9091

private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  allocation: sequential

database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h

dns:
  magic_dns: false
  nameservers:
    global:
      - 1.1.1.1
  override_local_dns: false

log:
  level: info

disable_check_updates: true
ephemeral_node_inactivity_timeout: 30m
EOF

    cat > "${COMPOSE_DIR}/headscale/docker-compose.yml" << EOF
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: always
    command: serve
    ports:
      - "${port}:${port}"
    volumes:
      - ${CONFIG_DIR}/headscale/config.yaml:/etc/headscale/config.yaml:ro
      - ${DATA_DIR}/headscale:/var/lib/headscale
EOF

    require_port "$port" headscale
    info "Starting Headscale…"
    dc "${COMPOSE_DIR}/headscale" up -d
    mark_installed headscale
    update_dashboard
    success "Headscale ready (no web UI — CLI only)"
    info  "Setup:"
    info  "  docker exec headscale headscale users create myuser"
    info  "  docker exec headscale headscale users list          # note the user ID"
    info  "  docker exec headscale headscale preauthkeys create --user USER_ID"
    info  "  On client: tailscale up --login-server http://${ip}:${port} --authkey YOUR_KEY"
    info  "Generate a new key per device. Add --reusable only if needed."
}

setup_uptimekuma() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/uptimekuma" "${DATA_DIR}/uptimekuma"

    local port="${SVC_PORT[uptimekuma]}"

    cat > "${COMPOSE_DIR}/uptimekuma/docker-compose.yml" << EOF
services:
  uptimekuma:
    image: louislam/uptime-kuma:1
    container_name: uptimekuma
    restart: always
    ports:
      - "${port}:3001"
    volumes:
      - ${DATA_DIR}/uptimekuma:/app/data
EOF

    require_port "$port" uptimekuma
    info "Starting Uptime Kuma…"
    dc "${COMPOSE_DIR}/uptimekuma" up -d
    mark_installed uptimekuma
    update_dashboard
    success "Uptime Kuma    → http://${ip}:${port}"
    info  "Create your admin account on first visit."
}

setup_netdata() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/netdata" "${DATA_DIR}/netdata"

    local port="${SVC_PORT[netdata]}"

    cat > "${COMPOSE_DIR}/netdata/docker-compose.yml" << EOF
services:
  netdata:
    image: netdata/netdata:stable
    container_name: netdata
    restart: always
    network_mode: host
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    volumes:
      - ${DATA_DIR}/netdata:/var/lib/netdata
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /etc/localtime:/etc/localtime:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - DOCKER_HOST=unix:///var/run/docker.sock
      - NETDATA_DISABLE_CLOUD=1
EOF
    require_port "$port" netdata
    info "Starting Netdata…"
    dc "${COMPOSE_DIR}/netdata" up -d
    mark_installed netdata
    update_dashboard
    success "Netdata        → http://${ip}:${port}"
}

setup_prometheus() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/prometheus" \
             "${CONFIG_DIR}/prometheus" \
             "${DATA_DIR}/prometheus"

    local port="${SVC_PORT[prometheus]}"

    cat > "${CONFIG_DIR}/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'netdata'
    metrics_path: /api/v1/allmetrics
    params:
      format: ['prometheus']
    honor_labels: true
    static_configs:
      - targets: ['localhost:19999']
EOF

    cat > "${COMPOSE_DIR}/prometheus/docker-compose.yml" << EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    network_mode: host
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.listen-address=:${port}'
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${DATA_DIR}/prometheus:/prometheus
    user: "65534:65534"
EOF

    chown -R 65534:65534 "${DATA_DIR}/prometheus"

    require_port "$port" prometheus
    info "Starting Prometheus…"
    dc "${COMPOSE_DIR}/prometheus" up -d
    mark_installed prometheus
    update_dashboard
    success "Prometheus     → http://${ip}:${port}"
}

setup_grafana() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/grafana" \
             "${CONFIG_DIR}/grafana/provisioning/datasources" \
             "${DATA_DIR}/grafana"

    local port="${SVC_PORT[grafana]}"
    local _env="${COMPOSE_DIR}/grafana/.env"
    local admin_pass; admin_pass=$(load_env_var "$_env" GF_ADMIN_PASSWORD)
    admin_pass=${admin_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Grafana credentials."

    cat > "${COMPOSE_DIR}/grafana/.env" << EOF
GF_ADMIN_PASSWORD=${admin_pass}
EOF
    chmod 600 "${COMPOSE_DIR}/grafana/.env"

    cat > "${CONFIG_DIR}/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://localhost:9090
    isDefault: true
    access: server
    editable: false
EOF

    cat > "${COMPOSE_DIR}/grafana/docker-compose.yml" << EOF
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    network_mode: host
    volumes:
      - ${CONFIG_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${DATA_DIR}/grafana:/var/lib/grafana
    environment:
      - GF_SERVER_HTTP_PORT=${port}
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=\${GF_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
EOF

    chown -R 472:472 "${DATA_DIR}/grafana"

    require_port "$port" grafana
    info "Starting Grafana…"
    dc "${COMPOSE_DIR}/grafana" up -d
    mark_installed grafana
    update_dashboard
    success "Grafana        → http://${ip}:${port}"
    info  "Login          → admin / (see ${COMPOSE_DIR}/grafana/.env)"
    info  "Prometheus datasource is pre-configured."
}

setup_woodpecker() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/woodpecker" "${DATA_DIR}/woodpecker"

    local _env="${COMPOSE_DIR}/woodpecker/.env"
    local agent_secret; agent_secret=$(load_env_var "$_env" WOODPECKER_AGENT_SECRET)
    agent_secret=${agent_secret:-$(gen_password)$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Woodpecker agent secret."
    local port="${SVC_PORT[woodpecker]}"

    cat > "${COMPOSE_DIR}/woodpecker/.env" << EOF
WOODPECKER_AGENT_SECRET=${agent_secret}
WOODPECKER_GITEA_CLIENT=REPLACE_WITH_FORGEJO_CLIENT_ID
WOODPECKER_GITEA_SECRET=REPLACE_WITH_FORGEJO_CLIENT_SECRET
EOF
    chmod 600 "${COMPOSE_DIR}/woodpecker/.env"

    cat > "${COMPOSE_DIR}/woodpecker/docker-compose.yml" << EOF
services:
  woodpecker-server:
    image: woodpeckerci/woodpecker-server:latest
    container_name: woodpecker-server
    restart: always
    ports:
      - "${port}:8000"
    volumes:
      - ${DATA_DIR}/woodpecker:/var/lib/woodpecker
    environment:
      - WOODPECKER_OPEN=false
      - WOODPECKER_HOST=http://${ip}:${port}
      - WOODPECKER_GITEA=true
      - WOODPECKER_GITEA_URL=http://${ip}:3000
      - WOODPECKER_GITEA_CLIENT=\${WOODPECKER_GITEA_CLIENT}
      - WOODPECKER_GITEA_SECRET=\${WOODPECKER_GITEA_SECRET}
      - WOODPECKER_AGENT_SECRET=\${WOODPECKER_AGENT_SECRET}

  woodpecker-agent:
    image: woodpeckerci/woodpecker-agent:latest
    container_name: woodpecker-agent
    restart: always
    depends_on:
      - woodpecker-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WOODPECKER_SERVER=woodpecker-server:9000
      - WOODPECKER_AGENT_SECRET=\${WOODPECKER_AGENT_SECRET}
EOF

    require_port "$port" woodpecker
    info "Starting Woodpecker CI…"
    dc "${COMPOSE_DIR}/woodpecker" up -d
    mark_installed woodpecker
    update_dashboard
    success "Woodpecker CI  → http://${ip}:${port}"
    warn  "OAuth setup required before Woodpecker is usable:"
    info  "  1. In Forgejo → Settings → Applications → OAuth2 Apps → Add"
    info  "     Name:         Woodpecker CI"
    info  "     Redirect URI: http://${ip}:${port}/authorize"
    info  "  2. Copy the Client ID and Secret into:"
    info  "     ${COMPOSE_DIR}/woodpecker/.env"
    info  "  3. Restart: sudo bash setup.sh --restart woodpecker"
}

setup_adguard() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/adguard" \
             "${DATA_DIR}/adguard/work" \
             "${DATA_DIR}/adguard/conf"

    local port="${SVC_PORT[adguard]}"

    # systemd-resolved holds port 53 — disable its stub listener
    if ss -tlnp 2>/dev/null | grep -q ':53 .*systemd-resolve'; then
        info "Disabling systemd-resolved stub listener (port 53)…"
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/no-stub.conf << 'EOF'
[Resolve]
DNSStubListener=no
EOF
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved
        success "systemd-resolved stub disabled."
    fi

    cat > "${COMPOSE_DIR}/adguard/docker-compose.yml" << EOF
services:
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: always
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "${port}:3000"
    volumes:
      - ${DATA_DIR}/adguard/work:/opt/adguardhome/work
      - ${DATA_DIR}/adguard/conf:/opt/adguardhome/conf
EOF

    require_port 53 adguard
    require_port "$port" adguard
    info "Starting AdGuard Home…"
    dc "${COMPOSE_DIR}/adguard" up -d
    mark_installed adguard
    update_dashboard
    success "AdGuard Home   → http://${ip}:${port}"
    info  "Complete the setup wizard on first visit."
    warn  "In the wizard, set web UI listen address to 0.0.0.0:3000 (not port 80)."
    warn  "Point your router's DNS to ${ip} for network-wide ad blocking."
}

setup_authentik() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/authentik" \
             "${DATA_DIR}/authentik/db" \
             "${DATA_DIR}/authentik/data" \
             "${DATA_DIR}/authentik/templates" \
             "${DATA_DIR}/authentik/certs"

    local port="${SVC_PORT[authentik]}"
    local _env="${COMPOSE_DIR}/authentik/.env"
    local db_pass; db_pass=$(load_env_var "$_env" AUTHENTIK_DB_PASSWORD)
    local secret_key; secret_key=$(load_env_var "$_env" AUTHENTIK_SECRET_KEY)
    db_pass=${db_pass:-$(gen_password)}
    secret_key=${secret_key:-$(gen_password)$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Authentik credentials."

    cat > "${COMPOSE_DIR}/authentik/.env" << EOF
AUTHENTIK_DB_PASSWORD=${db_pass}
AUTHENTIK_SECRET_KEY=${secret_key}
EOF
    chmod 600 "${COMPOSE_DIR}/authentik/.env"

    cat > "${COMPOSE_DIR}/authentik/docker-compose.yml" << EOF
services:
  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik-server
    restart: always
    command: server
    shm_size: 512mb
    ports:
      - "${port}:9443"
    volumes:
      - ${DATA_DIR}/authentik/data:/data
      - ${DATA_DIR}/authentik/templates:/templates
    environment:
      - AUTHENTIK_POSTGRESQL__HOST=authentik-db
      - AUTHENTIK_POSTGRESQL__USER=authentik
      - AUTHENTIK_POSTGRESQL__NAME=authentik
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${AUTHENTIK_DB_PASSWORD}
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}
      - AUTHENTIK_REDIS__HOST=authentik-redis
    depends_on:
      - authentik-db
      - authentik-redis

  authentik-worker:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik-worker
    restart: always
    command: worker
    shm_size: 512mb
    user: root
    volumes:
      - ${DATA_DIR}/authentik/data:/data
      - ${DATA_DIR}/authentik/certs:/certs
      - ${DATA_DIR}/authentik/templates:/templates
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - AUTHENTIK_POSTGRESQL__HOST=authentik-db
      - AUTHENTIK_POSTGRESQL__USER=authentik
      - AUTHENTIK_POSTGRESQL__NAME=authentik
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${AUTHENTIK_DB_PASSWORD}
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}
      - AUTHENTIK_REDIS__HOST=authentik-redis
    depends_on:
      - authentik-db
      - authentik-redis

  authentik-redis:
    image: redis:8-alpine
    container_name: authentik-redis
    restart: always

  authentik-db:
    image: postgres:16-alpine
    container_name: authentik-db
    restart: always
    environment:
      - POSTGRES_DB=authentik
      - POSTGRES_USER=authentik
      - POSTGRES_PASSWORD=\${AUTHENTIK_DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/authentik/db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d authentik -U authentik"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

    require_port "$port" authentik
    info "Starting Authentik…"
    dc "${COMPOSE_DIR}/authentik" up -d
    mark_installed authentik
    update_dashboard
    success "Authentik      → https://${ip}:${port}"
    warn  "IMPORTANT: Before using Authentik, go to this URL to create your admin account:"
    warn  "  https://${ip}:${port}/if/flow/initial-setup/"
    warn  "The main page will show 'Not Found' until you complete this step."
    warn  "Accept the self-signed certificate warning in your browser."
}

setup_ollama() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/ollama" \
             "${DATA_DIR}/ollama/models" \
             "${DATA_DIR}/ollama/webui"

    local port="${SVC_PORT[ollama]}"

    cat > "${COMPOSE_DIR}/ollama/docker-compose.yml" << EOF
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: always
    ports:
      - "11434:11434"
    volumes:
      - ${DATA_DIR}/ollama/models:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "${port}:8080"
    volumes:
      - ${DATA_DIR}/ollama/webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
EOF

    require_port 11434 ollama
    require_port "$port" ollama
    info "Starting Ollama + Open WebUI…"
    dc "${COMPOSE_DIR}/ollama" up -d
    mark_installed ollama
    update_dashboard
    success "Open WebUI     → http://${ip}:${port}"
    success "Ollama API     → http://${ip}:11434"
    info  "Create your account on first visit, then pull a model:"
    info  "  docker exec ollama ollama pull tinyllama"
    warn  "Small models only on Pi (tinyllama, phi). 7B+ models need 8GB+ RAM."
}

setup_linkding() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/linkding" "${DATA_DIR}/linkding"

    local port="${SVC_PORT[linkding]}"
    local _env="${COMPOSE_DIR}/linkding/.env"
    local superuser_pass; superuser_pass=$(load_env_var "$_env" LD_SUPERUSER_PASSWORD)
    superuser_pass=${superuser_pass:-$(gen_password)}
    [[ -f "$_env" ]] && info "Reusing existing Linkding credentials."

    cat > "${COMPOSE_DIR}/linkding/.env" << EOF
LD_SUPERUSER_PASSWORD=${superuser_pass}
EOF
    chmod 600 "${COMPOSE_DIR}/linkding/.env"

    cat > "${COMPOSE_DIR}/linkding/docker-compose.yml" << EOF
services:
  linkding:
    image: sissbruecker/linkding:latest
    container_name: linkding
    restart: always
    ports:
      - "${port}:9090"
    volumes:
      - ${DATA_DIR}/linkding:/etc/linkding/data
    environment:
      - LD_SUPERUSER_NAME=admin
      - LD_SUPERUSER_PASSWORD=\${LD_SUPERUSER_PASSWORD}
EOF

    require_port "$port" linkding
    info "Starting Linkding…"
    dc "${COMPOSE_DIR}/linkding" up -d
    mark_installed linkding
    update_dashboard
    success "Linkding       → http://${ip}:${port}"
    info  "Login          → admin / (see ${COMPOSE_DIR}/linkding/.env)"
}

setup_freshrss() {
    local ip; ip=$(get_current_ip)
    mkdir -p "${COMPOSE_DIR}/freshrss" "${DATA_DIR}/freshrss"

    local port="${SVC_PORT[freshrss]}"

    local tz
    tz=$(cat /etc/timezone 2>/dev/null \
         || timedatectl show --property=Timezone --value 2>/dev/null \
         || echo "UTC")

    cat > "${COMPOSE_DIR}/freshrss/docker-compose.yml" << EOF
services:
  freshrss:
    image: freshrss/freshrss:latest
    container_name: freshrss
    restart: always
    ports:
      - "${port}:80"
    volumes:
      - ${DATA_DIR}/freshrss/data:/var/www/FreshRSS/data
      - ${DATA_DIR}/freshrss/extensions:/var/www/FreshRSS/extensions
    environment:
      - TZ=${tz}
      - CRON_MIN=2,32
EOF

    require_port "$port" freshrss
    info "Starting FreshRSS…"
    dc "${COMPOSE_DIR}/freshrss" up -d
    mark_installed freshrss
    update_dashboard
    success "FreshRSS       → http://${ip}:${port}"
    info  "Create your admin account on first visit."
}

upgrade_service() {
    local name="$1"

    if ! is_installed "$name"; then
        warn "'${name}' is not installed — nothing to upgrade."
        return 0
    fi

    if [[ "$name" == "caddy" ]]; then
        zfs_snapshot "pre-upgrade-caddy-$(date +%Y%m%d-%H%M%S)"
        info "Upgrading Caddy…"
        apt-get update -qq && apt-get install -y -qq caddy
        systemctl restart caddy
        success "Caddy upgraded and restarted."
        return 0
    fi

    local compose_dir="${COMPOSE_DIR}/${name}"
    if [[ ! -f "${compose_dir}/docker-compose.yml" ]]; then
        warn "No compose file for ${name} — cannot upgrade."
        return 1
    fi

    zfs_snapshot "pre-upgrade-${name}-$(date +%Y%m%d-%H%M%S)"

    info "Pulling latest images for ${name}…"
    dc "$compose_dir" pull

    info "Recreating ${name} with new images…"
    dc "$compose_dir" up -d --remove-orphans

    success "${name} upgraded."
}

restart_service() {
    local name="$1"

    if ! is_installed "$name"; then
        warn "'${name}' is not installed — nothing to restart."
        return 0
    fi

    info "Restarting ${name}…"

    if [[ "$name" == "caddy" ]]; then
        systemctl restart caddy
        success "Caddy restarted."
        return 0
    fi

    local compose_dir="${COMPOSE_DIR}/${name}"
    if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
        dc "$compose_dir" restart
        success "${name} restarted."
    else
        docker restart "$name" 2>/dev/null \
            && success "${name} restarted." \
            || warn "Could not restart ${name} — container not found."
    fi
}

stop_service() {
    local name="$1"

    if ! is_installed "$name"; then
        warn "'${name}' is not installed — nothing to stop."
        return 0
    fi

    info "Stopping ${name}…"

    if [[ "$name" == "caddy" ]]; then
        systemctl stop caddy
        success "Caddy stopped."
        return 0
    fi

    local compose_dir="${COMPOSE_DIR}/${name}"
    if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
        dc "$compose_dir" stop
        success "${name} stopped."
    else
        docker stop "$name" 2>/dev/null \
            && success "${name} stopped." \
            || warn "Could not stop ${name} — container not found."
    fi
}

# uninstall_service <name> [purge=false] [confirmed=false]
# confirmed=true skips the interactive purge prompt (used by uninstall_all)
uninstall_service() {
    local name="$1" purge="${2:-false}" confirmed="${3:-false}"

    if ! is_installed "$name"; then
        warn "'${name}' is not installed — nothing to do."
        return 0
    fi

    info "Uninstalling ${name}…"

    if [[ "$name" == "caddy" ]]; then
        local blocking=()
        for svc in "${SVC_NAMES[@]}"; do
            [[ "${SVC_NEEDS_HTTPS[$svc]:-false}" == "true" ]] || continue
            is_installed "$svc" && blocking+=("$svc")
        done
        if [[ ${#blocking[@]} -gt 0 ]]; then
            die "Cannot uninstall Caddy while HTTPS services are still installed: ${blocking[*]}.
Uninstall them first, or use --uninstall-all."
        fi
        systemctl stop caddy    2>/dev/null || true
        systemctl disable caddy 2>/dev/null || true
        : > /etc/caddy/Caddyfile
        if [[ "$purge" == "true" ]]; then
            apt-get remove -y caddy 2>/dev/null || true
            rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            rm -f /etc/apt/sources.list.d/caddy-stable.list
            rm -f "${DATA_DIR}/caddy-root.crt"
            success "Caddy package removed."
        fi
        mark_uninstalled caddy
        success "Caddy stopped and disabled."
        return 0
    fi

    local compose_dir="${COMPOSE_DIR}/${name}"
    if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
        dc "$compose_dir" down --remove-orphans 2>/dev/null || true
    else
        docker rm -f "$name" 2>/dev/null || true
    fi

    rm -rf "$compose_dir"

    if [[ "$purge" == "true" ]]; then
        local do_purge=false
        if [[ "$confirmed" == "true" ]]; then
            do_purge=true
        else
            warn  "PURGE: This will permanently delete all data for '${name}'."
            warn  "This cannot be undone."
            printf "  Type the service name to confirm: "
            local confirm
            read -r confirm
            [[ "$confirm" == "$name" ]] && do_purge=true \
                || info "Purge cancelled — data kept at ${DATA_DIR}/${name}"
        fi
        if $do_purge; then
            rm -rf "${CONFIG_DIR}/${name}"
            rm -rf "${DATA_DIR}/${name}"
            success "Purged config and data for ${name}."
        fi
    fi

    mark_uninstalled "$name"

    if [[ "${SVC_NEEDS_HTTPS[$name]:-false}" == "true" ]]; then
        update_caddy
    fi

    update_dashboard

    success "${name} uninstalled."
}

uninstall_all() {
    local purge="${1:-false}"

    info "Uninstalling all services…"

    local confirmed=false
    if [[ "$purge" == "true" ]]; then
        warn  "PURGE: All service data under ${DATA_DIR}/ will be permanently deleted."
        warn  "This cannot be undone."
        printf "  Type 'yes' to confirm: "
        local confirm
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            info "Purge cancelled — proceeding with uninstall only (data kept)."
            purge=false
        else
            confirmed=true
        fi
    fi

    local -a installed=()
    for name in "${SVC_NAMES[@]}"; do
        is_installed "$name" && installed+=("$name")
    done

    local -a rev=()
    for (( i=${#installed[@]}-1; i>=0; i-- )); do
        rev+=("${installed[$i]}")
    done

    for name in "${rev[@]}"; do
        uninstall_service "$name" "$purge" "$confirmed"
    done

    if [[ "$purge" == "true" ]]; then
        remove_systemd_units
        rm -rf "${INSTALL_DIR}"
        success "All data purged. Install root removed."
    fi

    success "All services uninstalled."
}

purge_data() {
    local name="$1"

    if is_installed "$name"; then
        die "'${name}' is still installed. Run --uninstall ${name} first, then --purge ${name}."
    fi

    local data_dir="${DATA_DIR}/${name}"
    local config_dir="${CONFIG_DIR}/${name}"

    if [[ ! -d "$data_dir" && ! -d "$config_dir" ]]; then
        info "No leftover data found for '${name}' — nothing to do."
        return 0
    fi

    [[ -d "$data_dir" ]]   && info "Data   : $(du -sh "$data_dir"   2>/dev/null | cut -f1)  ${data_dir}"
    [[ -d "$config_dir" ]] && info "Config : $(du -sh "$config_dir" 2>/dev/null | cut -f1)  ${config_dir}"

    warn "This will permanently delete the above. This cannot be undone."
    printf "  Type the service name to confirm: "
    local confirm; read -r confirm
    if [[ "$confirm" != "$name" ]]; then
        info "Purge cancelled."
        return 0
    fi

    rm -rf "$data_dir" "$config_dir"
    success "Purged data for ${name}."
}

purge_all_data() {
    local -a orphans=()
    for name in "${SVC_NAMES[@]}"; do
        is_installed "$name" && continue
        { [[ -d "${DATA_DIR}/${name}" ]] || [[ -d "${CONFIG_DIR}/${name}" ]]; } \
            || continue
        orphans+=("$name")
    done

    if [[ ${#orphans[@]} -eq 0 ]]; then
        info "No orphaned data found — nothing to do."
        return 0
    fi

    info "Uninstalled services with leftover data:"
    for name in "${orphans[@]}"; do
        local sz; sz=$(du -sh "${DATA_DIR}/${name}" 2>/dev/null | cut -f1 || echo "?")
        info "  ${name}  (${sz})"
    done

    warn "This will permanently delete all of the above. This cannot be undone."
    printf "  Type 'yes' to confirm: "
    local confirm; read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Purge cancelled."
        return 0
    fi

    for name in "${orphans[@]}"; do
        rm -rf "${DATA_DIR}/${name}" "${CONFIG_DIR}/${name}"
        success "Purged ${name}."
    done
}

remove_systemd_units() {
    info "Removing self-hosting systemd units…"
    systemctl stop    self-hosting-ip-monitor 2>/dev/null || true
    systemctl disable self-hosting-ip-monitor 2>/dev/null || true
    rm -f /etc/systemd/system/self-hosting-ip-monitor.service
    systemctl daemon-reload
    success "Systemd units removed."
}

handle_ip_change() {
    local old_ip="$1"
    local new_ip="$2"

    info "IP change: ${old_ip} → ${new_ip}"

    mkdir -p "${LOGS_DIR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S')  ${old_ip} → ${new_ip}" >> "${LOGS_DIR}/ip-changes.log"

    for name in "${SVC_NAMES[@]}"; do
        [[ "${SVC_IP_AWARE[$name]:-false}" == "true" ]] || continue
        is_installed "$name" || continue

        case "$name" in
            dashboard)
                generate_homer_config "$new_ip"
                docker restart homer &>/dev/null || true
                success "dashboard: Homer config updated."
                ;;
            caddy)
                generate_caddyfile "$new_ip"
                systemctl reload-or-restart caddy
                sleep 2
                success "caddy: Caddyfile updated and reloaded."
                ;;
            headscale)
                local hs_cfg="${CONFIG_DIR}/headscale/config.yaml"
                if [[ -f "$hs_cfg" ]]; then
                    sed -i "s|${old_ip}|${new_ip}|g" "$hs_cfg"
                    dc "${COMPOSE_DIR}/headscale" up -d --force-recreate
                    success "headscale: config.yaml updated and restarted."
                fi
                ;;
            *)
                local compose_file="${COMPOSE_DIR}/${name}/docker-compose.yml"
                local env_file="${COMPOSE_DIR}/${name}/.env"
                [[ -f "$env_file" ]]     && sed -i "s|${old_ip}|${new_ip}|g" "$env_file"
                if [[ -f "$compose_file" ]]; then
                    sed -i "s|${old_ip}|${new_ip}|g" "$compose_file"
                    dc "${COMPOSE_DIR}/${name}" up -d --force-recreate
                    success "${name}: config updated and restarted."
                fi
                ;;
        esac
    done

    success "IP change complete. All services reconfigured for ${new_ip}."
}

create_ip_monitor_script() {
    mkdir -p "${SCRIPTS_DIR}"
    cat > "${SCRIPTS_DIR}/ip-monitor.sh" << EOF
#!/usr/bin/env bash
# ip-monitor.sh — polls for LAN IP changes and calls setup.sh --update-ip
# Managed by systemd unit: self-hosting-ip-monitor.service
set -euo pipefail

SETUP="${INSTALL_DIR}/setup.sh"
IP_FILE="${IP_FILE}"

get_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \\K[\\d.]+' | head -1 \
        || hostname -I 2>/dev/null | awk '{print \$1}'
}

while true; do
    current=\$(get_ip)
    stored=\$(cat "\${IP_FILE}" 2>/dev/null || echo "")
    if [[ -n "\$current" && "\$current" != "\$stored" ]]; then
        echo "\$(date '+%Y-%m-%d %H:%M:%S')  IP change detected: \${stored:-none} → \${current}"
        bash "\$SETUP" --update-ip "\$current" || true
    fi
    sleep 30
done
EOF
    chmod 755 "${SCRIPTS_DIR}/ip-monitor.sh"
    success "IP monitor script → ${SCRIPTS_DIR}/ip-monitor.sh"
}

install_systemd_services() {
    if [[ "${SCRIPT_PATH}" != "${INSTALL_DIR}/setup.sh" ]]; then
        if [[ -f "${INSTALL_DIR}/setup.sh" ]] && ! diff -q "${SCRIPT_PATH}" "${INSTALL_DIR}/setup.sh" &>/dev/null; then
            warn "This will overwrite ${INSTALL_DIR}/setup.sh with the version you're running."
            printf "  Continue? [Y/n] "
            local answer; read -r answer
            [[ "$answer" =~ ^[Nn]$ ]] && { info "Kept existing ${INSTALL_DIR}/setup.sh."; return 0; }
        fi
        cp "${SCRIPT_PATH}" "${INSTALL_DIR}/setup.sh"
        chmod 755 "${INSTALL_DIR}/setup.sh"
        info "Installed setup.sh → ${INSTALL_DIR}/setup.sh"
    fi

    if systemctl is-active --quiet self-hosting-ip-monitor 2>/dev/null; then
        return 0
    fi

    create_ip_monitor_script

    cat > /etc/systemd/system/self-hosting-ip-monitor.service << EOF
[Unit]
Description=Self-hosting LAN IP change monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash ${SCRIPTS_DIR}/ip-monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ip-monitor

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now self-hosting-ip-monitor
    success "ip-monitor service enabled and started."
}


main() {
    local do_all=false
    local do_uninstall_all=false
    local do_purge=false
    local do_list=false
    local do_list_installed=false
    local do_export_cert=false
    local update_ip=""
    local -a install_queue=()
    local -a uninstall_queue=()
    local -a restart_queue=()
    local -a stop_queue=()
    local -a purge_queue=()
    local -a upgrade_queue=()
    local do_snapshots=false
    local -a snapshot_queue=()
    local rollback_svc=""

    [[ $# -eq 0 ]] && { print_usage; exit 0; }


    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                print_usage; exit 0 ;;

            --list)
                do_list=true ;;

            --list-installed)
                do_list_installed=true ;;

            --all)
                do_all=true ;;

            --purge)
                if [[ -n "${2:-}" ]] && { is_valid_service "${2:-}" || [[ "${2:-}" == "all" ]]; }; then
                    shift
                    purge_queue+=("$1")
                else
                    do_purge=true
                fi
                ;;

            --uninstall-all)
                do_uninstall_all=true ;;

            --uninstall)
                shift
                [[ -z "${1:-}" ]] && die "--uninstall requires a service name. Run --list to see options."
                is_valid_service "$1"  || die "Unknown service: '$1'. Run --list to see available services."
                uninstall_queue+=("$1")
                ;;

            --stop)
                shift
                [[ -z "${1:-}" ]] && die "--stop requires a service name (or 'all')."
                if [[ "$1" == "all" ]]; then
                    for svc in "${SVC_NAMES[@]}"; do
                        is_installed "$svc" && stop_queue+=("$svc")
                    done
                else
                    is_valid_service "$1" || die "Unknown service: '$1'. Run --list to see available services."
                    stop_queue+=("$1")
                fi
                ;;

            --restart)
                shift
                [[ -z "${1:-}" ]] && die "--restart requires a service name (or 'all')."
                if [[ "$1" == "all" ]]; then
                    for svc in "${SVC_NAMES[@]}"; do
                        is_installed "$svc" && restart_queue+=("$svc")
                    done
                else
                    is_valid_service "$1" || die "Unknown service: '$1'. Run --list to see available services."
                    restart_queue+=("$1")
                fi
                ;;

            --export-cert)
                do_export_cert=true ;;

            --update-ip)
                shift
                [[ -z "${1:-}" ]] && die "--update-ip requires an IP address."
                [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
                    || die "Invalid IP address: '$1'"
                update_ip="$1"
                ;;

            --upgrade)
                shift
                [[ -z "${1:-}" ]] && die "--upgrade requires a service name (or 'all')."
                if [[ "$1" == "all" ]]; then
                    for svc in "${SVC_NAMES[@]}"; do
                        is_installed "$svc" && upgrade_queue+=("$svc")
                    done
                else
                    is_valid_service "$1" || die "Unknown service: '$1'. Run --list to see available services."
                    upgrade_queue+=("$1")
                fi
                ;;

            --snapshots)
                do_snapshots=true ;;

            --snapshot)
                shift
                [[ -z "${1:-}" ]] && die "--snapshot requires a service name (or 'all')."
                if [[ "$1" == "all" ]]; then
                    snapshot_queue+=("all")
                else
                    is_valid_service "$1" || die "Unknown service: '$1'. Run --list to see available services."
                    snapshot_queue+=("$1")
                fi
                ;;

            --rollback)
                shift
                [[ -z "${1:-}" ]] && die "--rollback requires a service name."
                is_valid_service "$1" || die "Unknown service: '$1'. Run --list to see available services."
                rollback_svc="$1"
                ;;

            --*)
                local svc="${1#--}"
                is_valid_service "$svc" || die "Unknown option: '$1'. Run --help for usage."
                install_queue+=("$svc")
                ;;

            *)
                die "Unexpected argument: '$1'. Run --help for usage."
                ;;
        esac
        shift
    done

    # --purge as modifier requires an uninstall target
    if $do_purge && [[ ${#uninstall_queue[@]} -eq 0 ]] && ! $do_uninstall_all; then
        die "--purge (as modifier) requires --uninstall <service> or --uninstall-all.
To delete data for an already-uninstalled service use: --purge <service|all>"
    fi


    if [[ ${#stop_queue[@]} -gt 0 ]]; then
        require_root
        detect_docker_compose
        for svc in "${stop_queue[@]}"; do
            stop_service "$svc"
        done
        exit 0
    fi


    if [[ ${#restart_queue[@]} -gt 0 ]]; then
        require_root
        detect_docker_compose
        for svc in "${restart_queue[@]}"; do
            restart_service "$svc"
        done
        exit 0
    fi


    $do_list           && { list_services;  exit 0; }
    $do_list_installed && { list_installed; exit 0; }


    if $do_export_cert; then
        require_root
        init_dirs
        export_caddy_cert
        exit 0
    fi


    require_root
    check_os
    install_docker
    check_prerequisites
    init_dirs
    detect_docker_compose
    zfs_detect


    if [[ -n "$update_ip" ]]; then
        local old_ip
        old_ip=$(cat "${IP_FILE}" 2>/dev/null || get_current_ip)
        if [[ "$old_ip" == "$update_ip" ]]; then
            dim "IP unchanged (${update_ip}), nothing to do."
            exit 0
        fi
        handle_ip_change "$old_ip" "$update_ip"
        echo "$update_ip" > "${IP_FILE}"
        exit 0
    fi


    if [[ ${#purge_queue[@]} -gt 0 ]]; then
        for target in "${purge_queue[@]}"; do
            if [[ "$target" == "all" ]]; then
                purge_all_data
            else
                purge_data "$target"
            fi
        done
        exit 0
    fi


    if [[ ${#upgrade_queue[@]} -gt 0 ]]; then
        for svc in "${upgrade_queue[@]}"; do
            upgrade_service "$svc"
        done
        exit 0
    fi

    if $do_snapshots; then
        zfs_detect
        zfs_list_snapshots
        exit 0
    fi

    if [[ ${#snapshot_queue[@]} -gt 0 ]]; then
        zfs_detect
        for target in "${snapshot_queue[@]}"; do
            if [[ "$target" == "all" ]]; then
                zfs_snapshot "manual-$(date +%Y%m%d-%H%M%S)"
            else
                zfs_snapshot "manual-${target}-$(date +%Y%m%d-%H%M%S)"
            fi
        done
        exit 0
    fi

    if [[ -n "$rollback_svc" ]]; then
        zfs_detect
        zfs_rollback "$rollback_svc"
        exit 0
    fi

    if $do_uninstall_all; then
        uninstall_all "$do_purge"
        exit 0
    fi
    if [[ ${#uninstall_queue[@]} -gt 0 ]]; then
        for svc in "${uninstall_queue[@]}"; do
            uninstall_service "$svc" "$do_purge"
        done
        exit 0
    fi


    $do_all && install_queue=("${SVC_NAMES[@]}")
    [[ ${#install_queue[@]} -eq 0 ]] && { print_usage; exit 0; }

    local -a final_queue=()

    local needs_dashboard=true
    for svc in "${install_queue[@]}"; do
        [[ "$svc" == "dashboard" ]] && needs_dashboard=false && break
    done
    is_installed dashboard && needs_dashboard=false
    $needs_dashboard && final_queue+=("dashboard")

    local needs_caddy=false
    for svc in "${install_queue[@]}"; do
        [[ "${SVC_NEEDS_HTTPS[$svc]:-false}" == "true" ]] && needs_caddy=true && break
    done
    local caddy_in_queue=false
    for svc in "${install_queue[@]}"; do
        [[ "$svc" == "caddy" ]] && caddy_in_queue=true && break
    done
    if $needs_caddy && ! $caddy_in_queue && ! is_installed caddy; then
        final_queue+=("caddy")
    fi

    final_queue+=("${install_queue[@]}")


    local current_ip
    current_ip=$(get_current_ip)
    echo "$current_ip" > "${IP_FILE}"

    header "Homelab Setup  v${VERSION}"
    info "Server IP    : ${C_BOLD}${current_ip}${C_RESET}"
    info "Install root : ${INSTALL_DIR}"
    blank


    local installed_count=0
    local -a failed_svcs=()
    for svc in "${final_queue[@]}"; do
        if is_installed "$svc"; then
            dim "  ↷ Skipping ${svc} (already installed)"
            continue
        fi
        header "Installing: ${svc}"
        if ! check_disk "$svc"; then
            failed_svcs+=("$svc")
            continue
        fi
        zfs_snapshot "pre-install-${svc}-$(date +%Y%m%d-%H%M%S)"
        if ( "setup_${svc}" ); then
            (( installed_count++ )) || true
        else
            warn "  ✗ ${svc} failed to install — skipping (see output above)"
            failed_svcs+=("$svc")
        fi
    done

    blank
    header "Summary"
    list_installed

    if [[ $installed_count -gt 0 ]]; then
        info "Credentials are in ${COMPOSE_DIR}/<service>/.env"
        info "To see all running containers: docker ps"
        blank
        header "System Services"
        install_systemd_services
    fi

    if [[ ${#failed_svcs[@]} -gt 0 ]]; then
        blank
        warn "The following service(s) failed to install:"
        for svc in "${failed_svcs[@]}"; do
            warn "  ✗ ${svc}"
        done
        warn "Re-run with --${failed_svcs[0]} (or each service individually) to retry."
    fi
    blank
}


main "$@"
