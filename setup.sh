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
echo "   === 1. UPDATING SYSTEM & INSTALLING CORE DEPENDENCIES ==="
echo "=============================================================================="
echo ""

# Set OS hostname to 'ai'
hostnamectl set-hostname ai

apt-get update
apt-get install -y \
  curl \
  python3 \
  nginx \
  avahi-daemon \
  dnsmasq \
  docker.io

# Enable Avahi daemon for mDNS resolution (ai.local)
systemctl enable --now avahi-daemon

echo ""
echo "=============================================================================="
echo "   === 2. CONFIGURING PLUG-AND-PLAY DIRECT ETHERNET NETWORK ==="
echo "=============================================================================="
echo ""

# Automatically detect active physical primary Ethernet interface (ignores loopback/wifi)
NET_IFACE=$(ip -o link show | awk -F': ' '$2 !~ "^lo|w=" {print $2; exit}')

if [ -z "$NET_IFACE" ]; then
  echo "Error: Could not automatically determine Ethernet interface."
  exit 1
fi

echo "Configuring network interface: ${NET_IFACE}"

# Apply static IP (192.168.1.1/24) via Netplan
cat << NETPLAN_EOF | tee /etc/netplan/01-direct-ethernet.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ${NET_IFACE}:
      addresses:
        - 192.168.1.1/24
      dhcp4: false
      optional: true
NETPLAN_EOF

# Fix Netplan permissions warning
chmod 600 /etc/netplan/01-direct-ethernet.yaml
netplan apply || true

# Stop systemd-resolved port 53 binding conflict for dnsmasq
systemctl stop systemd-resolved || true
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf || true
sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf || true
systemctl restart systemd-resolved || true

# Configure dnsmasq to serve dynamic IPs to client PCs and resolve ai.local
cat << DNSMASQ_EOF | tee /etc/dnsmasq.d/direct-cable.conf
interface=${NET_IFACE}
dhcp-range=192.168.1.50,192.168.1.150,255.255.255.0,12h
dhcp-option=option:dns-server,192.168.1.1
address=/ai.local/192.168.1.1
DNSMASQ_EOF

systemctl restart dnsmasq

# Enable Docker service and ensure non-root user group access
systemctl enable --now docker
if id "ai" &>/dev/null; then
  usermod -aG docker ai || true
fi

echo ""
echo "=============================================================================="
echo "   === 3. INSTALLING OLLAMA & PULLING LIGHTWEIGHT MODELS ==="
echo "=============================================================================="
echo ""

if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama binary..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

systemctl enable --now ollama

echo "Waiting for Ollama API daemon..."
until curl -s http://127.0.0.1:11434/api/version >/dev/null; do
    sleep 1
done

echo "Pulling lightweight vision model (moondream)..."
ollama pull moondream

echo "Pulling embedding model (nomic-embed-text)..."
ollama pull nomic-embed-text

echo ""
echo "=============================================================================="
echo "   === 4. STARTING OPEN WEBUI CONTAINER ==="
echo "=============================================================================="
echo ""

# Remove existing container if script is re-run
docker rm -f open-webui &>/dev/null || true

# Launch container with tool/function calling disabled to ensure zero frontend schema errors
docker run -d \
  --network=host \
  -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  -e WEBUI_AUTH=false \
  -e ENABLE_OLLAMA_TOOLS=false \
  -e ENABLE_FUNCTION_CALLING=false \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo ""
echo "=============================================================================="
echo "   === 5. CONFIGURING NGINX REVERSE PROXY ==="
echo "=============================================================================="
echo ""

cat << 'NGINX_EOF' | tee /etc/nginx/sites-available/ai-server
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSockets support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/ai-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo ""
echo "Waiting for Open WebUI backend to initialize..."
until curl -s http://127.0.0.1:8080 >/dev/null; do
    sleep 2
done

echo ""
echo "=============================================================================="
echo "   === COMPLETE! SERVER READY FOR CLIENT USE ==="
echo "=============================================================================="
echo ""
echo "   Access Points via Direct Cable Connection:"
echo "     • http://ai.local"
echo "     • http://192.168.1.1"
echo ""
echo "   SSH Access:"
echo "     • ssh ai@ai.local (Password: 1234)"
echo "=============================================================================="
