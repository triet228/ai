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

## Step 1: Start Temporary Host

1. Open a terminal (or Command Prompt) on your main Host computer in the folder containing `setup.sh`.
2. Start the Python HTTP server:
   ```
   python -m http.server 8000
   ```
4. Determine your main Host's Wi-Fi IP address:
   * **Windows:** Run `ipconfig` in Command Prompt. Note the IPv4 Address under Wireless LAN adapter.
   * **Linux / macOS:** Run `ip a` or `ifconfig` and note your wireless interface IP (e.g., `10.0.0.56`).

---

## Step 2: Download & Execute Deployment (Target Ubuntu Machine)

1. Connect the AI box to the same Wi-Fi network via Ethernet.
2. Open a terminal on the AI box and run command (replace `10.0.0.56` with your Host's IP):
   ```
   curl -sSL http://10.0.0.56:8000/setup.sh | sudo bash
   ```
4. Allow the process to complete. The script automatically handles system updates, GPU power management, network configuration, Docker/Ollama/Nginx setup, pulling `gemma4:26b`, and initializing Open WebUI.

---

## Step 3: Post-Deployment Hand-Off

1. Connect a direct Ethernet cable from the AI box to any laptop.
2. Restart laptop.
3. On the laptop, open a web browser and navigate to:
   * **Open WebUI:** `http://ai.local` (or `http://192.168.1.1`)

## Developer Note

### Ollama API
Ollama API can be accessed at `http://ai.local/ollama/` (or `http://192.168.1.1:11434`). You can run this command to test if the API is working:
```
curl.exe http://ai.local/ollama/api/tags
```

### Default SSH Access
To access the internal of the AI box, you can go to your terminal, run:
```
ssh ai@ai.local
```
Type in `yes` for fingerprint request and enter default password `1234`. Warning is that you might want to change the password for security purpose.
