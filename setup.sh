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
  git \
  python3 \
  nginx \
  avahi-daemon \
  dnsmasq \
  docker.io \
  nvidia-driver-550 \
  network-manager

# Enable Avahi daemon for mDNS resolution (ai.local)
systemctl enable --now avahi-daemon

# Enable Docker service and ensure non-root user group access
systemctl enable --now docker
if id "ai" &>/dev/null; then
  usermod -aG docker ai || true
fi

echo ""
echo "=============================================================================="
echo "   === 2. CONFIGURING OLLAMA, SPEED OPTIMIZATIONS & PRELOADER ==="
echo "=============================================================================="
echo ""

if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama binary..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Configure Ollama environment variables for network access, fast switching & queueing
echo "Applying Ollama network binding, speed, and queueing optimizations..."
mkdir -p /etc/systemd/system/ollama.service.d/
cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_MAX_QUEUE=512"
EOF

systemctl daemon-reload
systemctl enable --now ollama

echo "Waiting for Ollama API daemon..."
until curl -s http://127.0.0.1:11434/api/version >/dev/null; do
    sleep 1
done

# Ensure gemma4:26b is pulled for preloading if not already present
if ! ollama list | grep -q "gemma4:26b"; then
    echo "Pulling gemma4:26b for system startup preloading..."
    ollama pull gemma4:26b || true
fi

# Create boot/restart service to auto-load gemma4:26b into RAM/VRAM
echo "Configuring automatic boot and service-restart preloader for gemma4:26b..."
cat <<EOF > /etc/systemd/system/preload-ollama.service
[Unit]
Description=Preload Gemma 26B into VRAM on Boot or Ollama Restart
After=ollama.service
BindsTo=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -s http://127.0.0.1:11434/api/generate -d '{"model": "gemma4:26b", "keep_alive": -1}'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target ollama.service
EOF

systemctl daemon-reload
systemctl enable preload-ollama.service
systemctl start preload-ollama.service || true

echo ""
echo "=============================================================================="
echo "   === 3. STARTING OPEN WEBUI CONTAINER ==="
echo "=============================================================================="
echo ""

# Pre-pull image while internet is active
docker pull ghcr.io/open-webui/open-webui:main

# Remove existing container if script is re-run
docker rm -f open-webui &>/dev/null || true

# Launch container with backend task queuing and infinite model keep-alive
docker run -d \
  --network=host \
  -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  -e OLLAMA_KEEP_ALIVE=-1 \
  -e WEBUI_AUTH=false \
  -e ENABLE_OLLAMA_TOOLS=false \
  -e ENABLE_FUNCTION_CALLING=false \
  -e ENABLE_QUEUE=true \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo ""
echo "=============================================================================="
echo "   === 4. CONFIGURING NGINX REVERSE PROXY ==="
echo "=============================================================================="
echo ""

echo "server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Open WebUI Frontend / API
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSockets support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_cache_bypass \$http_upgrade;
    }

    # Direct Ollama API Proxy (Port 80 routing without API key requirement)
    location /ollama/ {
        proxy_pass http://127.0.0.1:11434/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}" > /etc/nginx/sites-available/ai-server

ln -sf /etc/nginx/sites-available/ai-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo ""
echo "=============================================================================="
echo "   === 5. CONFIGURING PLUG-AND-PLAY DIRECT ETHERNET NETWORK ==="
echo "=============================================================================="
echo ""

# Automatically detect active physical primary Ethernet interface
NET_IFACE=$(ip -o link show | awk -F': ' '$2 !~ "^(lo|wl|docker|veth|br-)" {print $2; exit}')

if [ -z "$NET_IFACE" ]; then
  echo "Error: Could not automatically determine Ethernet interface."
  exit 1
fi

echo "Configuring network interface: ${NET_IFACE}"

# Apply static IP (192.168.1.1/24) via Netplan
echo "network:
  version: 2
  renderer: networkd
  ethernets:
    ${NET_IFACE}:
      addresses:
        - 192.168.1.1/24
      dhcp4: false
      optional: true" > /etc/netplan/01-direct-ethernet.yaml

chmod 600 /etc/netplan/01-direct-ethernet.yaml
netplan apply || true

# Force IP assignment onto interface immediately
ip addr add 192.168.1.1/24 dev ${NET_IFACE} 2>/dev/null || true
ip link set ${NET_IFACE} up || true

# Clean up any pre-existing dnsmasq configs
rm -rf /etc/dnsmasq.d/*

# Comment out global bind-interfaces from base dnsmasq config if present
sed -i 's/^bind-interfaces/#bind-interfaces/' /etc/dnsmasq.conf

# Write plug-and-play dnsmasq configuration
cat <<EOF > /etc/dnsmasq.d/direct-cable.conf
interface=${NET_IFACE}
bind-dynamic
dhcp-range=192.168.1.50,192.168.1.150,255.255.255.0,12h
dhcp-option=option:dns-server,192.168.1.1
dhcp-option=option:router,192.168.1.1
address=/ai.local/192.168.1.1
EOF

systemctl restart dnsmasq

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
echo "     • Ollama Proxy: http://ai.local/ollama/"
echo "     • Ollama Direct: http://ai.local:11434"
echo ""
echo "   SSH Access:"
echo "     • ssh ai@ai.local (Password: 1234)"
echo "=============================================================================="
