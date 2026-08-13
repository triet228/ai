# Server Deployment Guide (Direct Point-to-Point AI Server)

Quick-start guide to transfer and deploy `setup.sh` onto a fresh Ubuntu installation over local Wi-Fi, configuring a plug-and-play direct Ethernet AI server.

---

## What `setup.sh` Automates

* **NVIDIA Driver & GPU Power Management:** Installs driver 550 and configures a persistent **180W power cap** with persistence mode enabled (`nvidia-power-limit.service`).
* **Ollama Optimizations:** Configures network bindings, concurrent model options, queue limits, and automatic model preloading (`preload-ollama.service`).
* **Model Deployment:** Automatically pulls and preloads **`gemma4:26b`** into VRAM.
* **Open WebUI & Nginx Proxy:** Deploys Open WebUI via Docker and sets up Nginx as a reverse proxy for WebUI and direct Ollama API access.
* **Plug-and-Play Networking:** Automatically configures static IP (`192.168.1.1`), DHCP server via `dnsmasq`, and mDNS resolution (`ai.local`).

---

## Step 1: Start Temporary Host Server (Main PC)

1. Open a terminal (or Command Prompt) on your main computer in the folder containing `setup.sh`.
2. Start the Python HTTP server:
   ```
   python -m http.server 8000
   ```
4. Determine your main PC's Wi-Fi IP address:
   * **Windows:** Run `ipconfig` in Command Prompt. Note the IPv4 Address under Wireless LAN adapter.
   * **Linux / macOS:** Run `ip a` or `ifconfig` and note your wireless interface IP (e.g., `10.0.0.56`).

---

## Step 2: Download & Execute Deployment (Target Ubuntu Machine)

1. Connect the target Ubuntu machine to the same Wi-Fi network.
2. Open a terminal on the target machine and run the one-liner command (replace `10.0.0.56` with your main PC's IP):
   ```
   curl -sSL http://10.0.0.56:8000/setup.sh | sudo bash
   ```
4. Allow the process to complete. The script automatically handles system updates, GPU power management, network configuration, Docker/Ollama/Nginx setup, pulling `gemma4:26b`, and initializing Open WebUI.

---

## Step 3: Post-Deployment Hand-Off

1. Stop the Python server on your main PC by pressing `Ctrl + C`.
2. Disconnect the target machine from Wi-Fi.
3. Connect a direct Ethernet cable from the server to any client machine.
4. On the client machine, open a web browser and navigate to:
   * **WebUI:** http://ai.local or http://192.168.1.1
   * **Ollama API (Proxied):** http://ai.local/ollama/
   * **Ollama API (Direct):** http://ai.local:11434

### Default SSH Access
```
ssh ai@ai.local
```
Default Password is 1234.
