# Hardening Ubuntu: Secure DNS with DNSCrypt-Proxy and an "Iron Curtain" Firewall

> **Tested on:** Ubuntu 24.04 LTS | **VPN:** NordVPN (NordLynx / OpenVPN) | **DNS:** DNSCrypt-Proxy

---

In our current scenario, we need to protect a Linux workstation (like a Raspberry Pi or a laptop) from tracking, DNS hijacking, and unauthorized network exposure. When we work in public networks or need high privacy, a standard configuration isn't enough.

To solve this, we are going to implement a two-layer defense:

- **DNSCrypt-Proxy** — Encrypted DNS lookups preventing your ISP from seeing what sites you visit
- **"Iron Curtain" Firewall** — A custom UFW script enforcing a strict "VPN-only" killswitch policy

---

## Requirements

- Ubuntu 22.04 or later (or any Debian-based distro like Kali)
- Root or sudo access
- A VPN provider (pre-configured for **NordVPN** / OpenVPN)
- Basic knowledge of Bash and Networking

---

## Architecture Overview

### DNSCrypt-Proxy
A tool that encrypts DNS traffic using the DNSCrypt or DNS-over-HTTPS (DoH) protocols, preventing your ISP from seeing what sites you visit.

### UFW (Uncomplicated Firewall)
Used to create a "Nuclear Default" where all traffic is denied unless specifically allowed through the VPN tunnel.

### NordLynx / tun0
These are the network interfaces for our VPN. The goal is to ensure that if the VPN drops, the internet cuts off entirely (a **killswitch**).

---

## Step 0: Installation

### 1. Install DNSCrypt-Proxy

Run the install script to download and set up DNSCrypt-Proxy:

```bash
./linux/install.sh
```

This will:
- Download DNSCrypt-Proxy from the official releases
- Install it to `~/applications/dnscrypt-proxy`
- Copy the `dnscrypt-proxy.toml` configuration
- Register it as a systemd service

### 2. Start DNSCrypt-Proxy

```bash
~/applications/dnscrypt-proxy/dnscrypt-proxy --config dnscrypt-proxy.toml --service install
sudo systemctl enable dnscrypt-proxy
sudo systemctl start dnscrypt-proxy
```

---

## Step 1: Configuring DNSCrypt-Proxy

First, we need to configure our DNS provider. In the `dnscrypt-proxy.toml` file, we pin our traffic to Cloudflare for speed and reliability.

```toml
server_names = ['cloudflare']
ipv4_servers = true
ipv6_servers = false  # IPv6 is disabled for security
dnscrypt_servers = true
doh_servers = true
require_nolog = true
require_nofilter = true
```

> **Note:** We set `ipv6_servers = false`. Since IPv6 can bypass standard firewall rules if not configured correctly, we disable it entirely at the kernel level to prevent "leaks."

---

## Step 2: The "Iron Curtain" Firewall Script

The script performs a "Nuclear Reset" of your firewall. It starts by denying everything:

```bash
# Reset firewall to Nuclear Default
ufw --force reset
ufw default deny incoming
ufw default deny outgoing
ufw default deny routed
```

Now that the system is totally locked down, we selectively allow traffic. First, we allow the loopback interface so DNSCrypt-Proxy can talk to the system locally:

```bash
# Allow loopback for DNSCrypt
ufw allow out on lo
ufw allow in on lo
```

### Handling VPN and Local Discovery

A common problem with strict firewalls is losing access to your router or local SSH. We handle this by adding specific rules for the local network (`192.168.100.0/24`) and then allowing the VPN protocols (UDP 1194 for OpenVPN and 51820 for NordLynx):

```bash
# Allow VPN Handshake
ufw allow out on wlan0 to any port 1194 proto udp
ufw allow out on wlan0 to any port 51820 proto udp

# Allow traffic through the tunnel only
for IFACE in tun0 nordlynx; do
    ufw allow out on $IFACE to any port 443 proto tcp
    ufw allow out on $IFACE to any port 80 proto tcp
done
```

The script also includes a **"Step 8"** which uses `ip rule` to ensure that local traffic (like accessing your router at `192.168.100.1`) bypasses the VPN routing table. This is critical for engineers who need to maintain local connectivity while staying anonymous to the outside world.

---

## Step 3: Docker and Database Isolation

If you are a developer, you likely use Docker. By default, Docker bypasses UFW rules, which is a massive security risk. Our script addresses this by explicitly managing the `docker0` interface:

```bash
# Allow Docker to reach host services for development (Port 3000, 8080)
ufw allow in on docker0 to 127.0.0.1 port 3000
ufw allow in from 172.16.0.0/12 to any port 18080 proto tcp

# Deny all other docker0 outbound
ufw deny out on docker0
```

This ensures your containers can only talk to what they need and nothing else.

---

## How to Test the Project

Once you run the script, your internet should stop working immediately. This is expected! You must now connect to your VPN.

1. **Run the script:**
   ```bash
   sudo ./linux/configure-firewall.sh
   ```

2. **Connect VPN:**
   ```bash
   nordvpn connect
   ```

3. **Verify Protection:**
   ```bash
   curl --interface wlan0 https://ifconfig.me
   ```
   This command should **fail**. If it succeeds, your "Iron Curtain" has a hole, and your real IP is leaking!

---

## Conclusion and Next Steps

Using this configuration, you have transformed a standard Ubuntu installation into a high-security workstation. You now have encrypted DNS and a firewall that prevents any data from leaving your computer outside of the encrypted VPN tunnel.

The next step will be to automate this script to run every time a network interface changes, which I will cover in a future publication.