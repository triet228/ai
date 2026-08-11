#!/bin/bash
set -eo pipefail

# ------------------------------------------------------------------------------
# PRE-FLIGHT CHECK: Ensure execution as root
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  echo "Usage: sudo bash $0"
  exit 1
fi

echo ""
echo "=============================================================================="
echo "   === 1. REMOVING OPEN WEBUI & OLLAMA MODELS ==="
echo "=============================================================================="
echo ""

# Stop and remove Open WebUI container + volume
if command -v docker &>/dev/null; then
  echo "Stopping and removing Open WebUI container and volume..."
  docker rm -f open-webui &>/dev/null || true
  docker volume rm open-webui &>/dev/null || true
fi

# Stop Ollama service and remove downloaded models
if command -v ollama &>/dev/null; then
  echo "Removing local Ollama models..."
  ollama rm qwen2.5:0.5b &>/dev/null || true
  ollama rm moondream &>/dev/null || true
  ollama rm nomic-embed-text &>/dev/null || true
fi

systemctl stop ollama &>/dev/null || true

echo ""
echo "=============================================================================="
echo "   === 2. RESETTING NGINX CONFIGURATION ==="
echo "=============================================================================="
echo ""

# Remove reverse proxy config
rm -f /etc/nginx/sites-available/ai-server
rm -f /etc/nginx/sites-enabled/ai-server

# Restore default Nginx site if Nginx is installed
if [ -d /etc/nginx/sites-available ]; then
  cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  systemctl restart nginx &>/dev/null || true
fi

echo ""
echo "=============================================================================="
echo "   === 3. RESTORING NETWORK & DNS CONFIGURATIONS ==="
echo "=============================================================================="
echo ""

# Stop dnsmasq and wipe drop-in configuration
systemctl stop dnsmasq &>/dev/null || true
rm -rf /etc/dnsmasq.d/*

# Remove Netplan static direct ethernet config
rm -f /etc/netplan/01-direct-ethernet.yaml

# Re-enable systemd-resolved stub listener
rm -f /etc/systemd/resolved.conf.d/no-stub.conf
systemctl restart systemd-resolved.service systemd-resolved-monitor.socket systemd-resolved-varlink.socket &>/dev/null || true
systemctl restart systemd-resolved &>/dev/null || true

# Re-apply default Netplan
if command -v netplan &>/dev/null; then
  netplan apply || true
fi

# Reset OS hostname to default 'ubuntu'
hostnamectl set-hostname ubuntu || true

echo ""
echo "=============================================================================="
echo "   === CLEANUP COMPLETE! SYSTEM READY FOR RETESTING ==="
echo "=============================================================================="
echo ""
