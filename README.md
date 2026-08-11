# Server Deployment Guide (Direct Point-to-Point AI Server)

Quick-start guide to transfer and deploy setup.sh onto a fresh Ubuntu installation over local Wi-Fi, configuring a plug-and-play direct Ethernet AI server.

---

## Step 1: Start Temporary Host Server (Main PC)

1. Open a terminal (or Command Prompt) on your main computer in the folder containing setup.sh.
2. Start the Python HTTP server:
   ```
   python -m http.server 8000
   ```
4. Determine your main PC's Wi-Fi IP address:
   - Windows: Run ipconfig in Command Prompt. Note the IPv4 Address under Wireless LAN adapter.
   - Linux/macOS: Run ip a or ifconfig and note your wireless interface IP (e.g., `10.0.0.56`).

---

## Step 2: Download & Execute Deployment (Target Ubuntu Machine)

1. Connect the fresh Ubuntu installation to the same Wi-Fi network.
2. Open a terminal and run the one-liner command:
   ```
   curl -sSL http://10.0.0.56:8000/setup.sh | sudo bash
   ```

4. Allow the process to complete. The script automates system updates, network configuration, Docker/Ollama/Nginx installation, model pulls (moondream and nomic-embed-text), and Open WebUI initialization.

---

## Step 3: Post-Deployment Hand-Off

1. Stop the Python server on your main PC by pressing Ctrl + C.
2. Disconnect the target machine from Wi-Fi.
3. Connect a direct Ethernet cable from the server to any client machine.
4. On the client machine, open a web browser and navigate to:
   - http://ai.local or http://192.168.1.1
