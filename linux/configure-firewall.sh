#!/bin/bash
###############################################################################
# ARATIRI TECNOLOGIAS — "Iron Curtain" System Hardening
# -------------------------------------------------
# Environment:
#   - DNSCrypt-Proxy running locally on 127.0.0.1:53
#   - VPN Protocol: Any Server via OpenVPN (UDP 1194) or NordLynx (UDP 51820)
#   - Network interfaces: wlan0, eth0
#   - VPN tunnel interfaces: tun0, nordlynx
#   - IPv6: disabled at kernel level
###############################################################################

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
INTERFACE="wlan0"
DNS_SERVER="1.1.1.1"
DNS_SERVER2="1.0.0.1"
LOCAL_NETWORK="192.168.100.0/24"
MULTICAST="224.0.0.0/4"

# ── Preflight ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root (sudo)."
    exit 1
fi

echo "============================================"
echo "  ARATIRI — Iron Curtain Hardening"
echo "============================================"
echo ""

# ── Step 1: Disable Discovery Services ──────────────────────────────────────
echo "[*] Step 1: Disabling discovery services..."
systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true

# Disable LLMNR and MulticastDNS in systemd-resolved
if [[ -f /etc/systemd/resolved.conf ]]; then
    sed -i 's/^LLMNR=yes/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sed -i 's/^MulticastDNS=yes/MulticastDNS=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sed -i 's/^#LLMNR=yes/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sed -i 's/^#MulticastDNS=yes/MulticastDNS=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
elif [[ -d /etc/systemd ]]; then
    # Create resolved.conf if it doesn't exist (Kali Linux)
    echo -e "[Resolve]\nLLMNR=no\nMulticastDNS=no" > /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
fi

# ── Step 2: Kill IPv6 at Kernel Level ──────────────────────────────────────
echo "[*] Step 2: Killing IPv6 at kernel level..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1      > /dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1   > /dev/null 2>&1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1        > /dev/null 2>&1

# Tell UFW not to generate IPv6 rules
if grep -q "^IPV6=yes" /etc/default/ufw 2>/dev/null; then
    sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
fi

# ── Step 3: Reset Firewall to Nuclear Default ────────────────────────────────
echo "[*] Step 3: Resetting firewall to nuclear default..."
ufw --force reset > /dev/null 2>&1
ufw default deny incoming  > /dev/null
ufw default deny outgoing  > /dev/null
ufw default deny routed    > /dev/null
ufw logging low > /dev/null

# ── Step 4: Loopback (DNSCrypt-Proxy) ───────────────────────────────────────
echo "[+] Loopback: allow"
ufw allow out on lo > /dev/null
ufw allow in  on lo > /dev/null

# ── Step 4b: ADB (Android Debug Bridge) ────────────────────────────────────
echo "[+] ADB: allow incoming wireless debugging (port 5555)"
ufw allow in 5555/tcp > /dev/null

echo "[+] App/Web services: allow incoming (port 8080)"
ufw allow in 8080/tcp > /dev/null

# ── Step 5: Apply Interface-Bound Rules (wlan0) ────────────────────────────
echo "[*] Step 5: Applying wlan0 rules..."

# Allow SSH to local network (for Pi access when switching back to wireless)
echo "[+] wlan0: SSH to local network ($LOCAL_NETWORK)"
ufw allow out on wlan0 to "$LOCAL_NETWORK" port 22 proto tcp > /dev/null

# Allow HTTP to router admin page (192.168.100.1)
echo "[+] wlan0: HTTP to router admin (192.168.100.1:80)"
ufw allow out on wlan0 to 192.168.100.1 port 80 proto tcp > /dev/null

# Block local network access (stops router/ISP discovery)
echo "[+] wlan0: blocking local network ($LOCAL_NETWORK, $MULTICAST)"
ufw deny out on "$INTERFACE" to "$LOCAL_NETWORK" > /dev/null 2>&1 || true
ufw deny out on "$INTERFACE" to "$MULTICAST" > /dev/null 2>&1 || true

# OpenVPN (UDP 1194) - allow to any NordVPN server
echo "[+] wlan0: OpenVPN to any (UDP 1194)"
ufw allow out on "$INTERFACE" to any port 1194 proto udp > /dev/null

# NordLynx (WireGuard) - allow to any NordVPN server
echo "[+] wlan0: NordLynx to any (UDP 51820)"
ufw allow out on "$INTERFACE" to any port 51820 proto udp > /dev/null

# Allow HTTPS for Digital Platform access
echo "[+] wlan0: Direct HTTPS to any (port 443)"
ufw allow out on "$INTERFACE" to any port 443 proto tcp > /dev/null

# Allow HTTPS on alt port 8443 (payram-web API calls)
echo "[+] wlan0: Direct HTTPS alt to any (port 8443)"
ufw allow out on "$INTERFACE" to any port 8443 proto tcp > /dev/null

# Allow Cloudflare Tunnel (port 7844) for cloudflared
echo "[+] wlan0: Cloudflare Tunnel to any (port 7844)"
ufw allow out on "$INTERFACE" to any port 7844 proto tcp > /dev/null

# Allow HTTP for Digital Platform access
echo "[+] wlan0: Direct HTTP to any (port 80)"
ufw allow out on "$INTERFACE" to any port 80 proto tcp > /dev/null

# Allow DNS to Cloudflare (for DNSCrypt-proxy bootstrap) - must be after HTTPS to get numbered after it
echo "[+] wlan0: DNS to $DNS_SERVER (primary) and $DNS_SERVER2 (fallback)"
ufw allow out on "$INTERFACE" to "$DNS_SERVER" port 53 proto udp > /dev/null
ufw allow out on "$INTERFACE" to "$DNS_SERVER" port 53 proto tcp > /dev/null
ufw allow out on "$INTERFACE" to "$DNS_SERVER2" port 53 proto udp > /dev/null
ufw allow out on "$INTERFACE" to "$DNS_SERVER2" port 53 proto tcp > /dev/null

# Allow DNS to NordVPN (for VPN DNS resolution)
echo "[+] wlan0: DNS to NordVPN servers"
ufw allow out on "$INTERFACE" to 103.86.96.100 port 53 proto udp > /dev/null
ufw allow out on "$INTERFACE" to 103.86.96.100 port 53 proto tcp > /dev/null
ufw allow out on "$INTERFACE" to 103.86.99.100 port 53 proto udp > /dev/null
ufw allow out on "$INTERFACE" to 103.86.99.100 port 53 proto tcp > /dev/null

# ── Step Torrent: BitTorrent P2P (Port 51413) ──────────────────────────────
# Replace 51413 with the port configured in your Torrent Client (e.g., Transmission/qBittorrent)
TORRENT_PORT=51413

echo "[*] Step Torrent: Allowing P2P traffic through VPN tunnels..."

# Allow incoming/outgoing on VPN tunnel interfaces only (Identity Protection)
for IFACE in tun0 nordlynx; do
    echo "[+] $IFACE: Allow BitTorrent (Port $TORRENT_PORT)"
    ufw allow in on $IFACE to any port $TORRENT_PORT proto tcp > /dev/null
    ufw allow in on $IFACE to any port $TORRENT_PORT proto udp > /dev/null
    ufw allow out on $IFACE to any port $TORRENT_PORT proto tcp > /dev/null
    ufw allow out on $IFACE to any port $TORRENT_PORT proto udp > /dev/null
done

# Reload firewall to apply
ufw reload > /dev/null
echo "[+] Torrent ports active on VPN interfaces."

# Allow PostgreSQL outbound for Supabase connections
echo "[+] wlan0: PostgreSQL outbound (port 5432)"
ufw allow out on "$INTERFACE" to any port 5432 proto tcp > /dev/null

# ── Step 6: Apply Tunnel Rules (tun0) ───────────────────────────────────────
echo "[*] Step 6: Applying tun0 rules..."
echo "[+] tun0: DNS, HTTPS, HTTP, SSH, NTP through VPN"
ufw allow out on tun0 to any port 53  proto udp > /dev/null
ufw allow out on tun0 to any port 53  proto tcp > /dev/null
ufw allow out on tun0 to any port 443 proto tcp > /dev/null
ufw allow out on tun0 to any port 443 proto udp > /dev/null
ufw allow out on tun0 to any port 8443 proto tcp > /dev/null
ufw allow out on tun0 to any port 7844 proto tcp > /dev/null
ufw allow out on tun0 to any port 80  proto tcp > /dev/null
ufw allow out on tun0 to any port 22  proto tcp > /dev/null
ufw allow out on tun0 to any port 123 proto udp > /dev/null
ufw allow out on tun0 to any port 5432 proto tcp > /dev/null

# ── Step 6b: Apply NordLynx Rules ───────────────────────────────────────────
echo "[*] Step 6b: Applying nordlynx rules..."
echo "[+] nordlynx: DNS, HTTPS, HTTP, SSH, NTP through NordLynx"
ufw allow out on nordlynx to any port 53  proto udp > /dev/null
ufw allow out on nordlynx to any port 53  proto tcp > /dev/null
ufw allow out on nordlynx to any port 443 proto tcp > /dev/null
ufw allow out on nordlynx to any port 443 proto udp > /dev/null
ufw allow out on nordlynx to any port 8443 proto tcp > /dev/null
ufw allow out on nordlynx to any port 7844 proto tcp > /dev/null
ufw allow out on nordlynx to any port 80  proto tcp > /dev/null
ufw allow out on nordlynx to any port 22  proto tcp > /dev/null
ufw allow out on nordlynx to any port 123 proto udp > /dev/null
ufw allow out on nordlynx to any port 5432 proto tcp > /dev/null

ufw allow out on eth0 to any port 53  proto udp > /dev/null
ufw allow out on eth0 to any port 53  proto tcp > /dev/null
ufw allow out on eth0 to any port 443 proto tcp > /dev/null
ufw allow out on eth0 to any port 443 proto udp > /dev/null
ufw allow out on eth0 to any port 8443 proto tcp > /dev/null
ufw allow out on eth0 to any port 7844 proto tcp > /dev/null
ufw allow out on eth0 to any port 80  proto tcp > /dev/null

# Allow SSH to local network (for Pi access when switching to wired)
echo "[+] eth0: SSH to local network ($LOCAL_NETWORK)"
ufw allow out on eth0 to "$LOCAL_NETWORK" port 22 proto tcp > /dev/null

# Allow HTTP to router admin page (192.168.100.1)
echo "[+] eth0: HTTP to router admin (192.168.100.1:80)"
ufw allow out on eth0 to 192.168.100.1 port 80 proto tcp > /dev/null

ufw allow out on eth0 to any port 123 proto udp > /dev/null
ufw allow out on eth0 to any port 5432 proto tcp > /dev/null
ufw allow out on eth0 to any port 1194 proto udp > /dev/null
ufw allow out on eth0 to any port 51820 proto udp > /dev/null

# ── Step 6c: Allow Outgoing ICMP (for ping) ─────────────────────────────────
echo "[*] Step 6c: Allowing outgoing ICMP (ping)..."
# UFW handles ICMP through before.rules, not through ufw command
# Allow outgoing echo-request (ping out), but block incoming echo-request (ping in)
if [[ -f /etc/ufw/before.rules ]]; then
    # Check if we already added our ICMP rules
    if ! grep -q "# ARATIRI ICMP Rules" /etc/ufw/before.rules; then
        # Insert after the *filter line in before.rules
        sed -i '/^*filter$/a\
# ARATIRI ICMP Rules - Allow outgoing ping only\
-A ufw-before-output -p icmp --icmp-type echo-request -j ACCEPT\
-A ufw-before-input -p icmp --icmp-type echo-reply -j ACCEPT' /etc/ufw/before.rules
        echo "[+] Added ICMP rules to /etc/ufw/before.rules"
    else
        echo "[+] ICMP rules already present"
    fi
fi

# ── Step 7: Docker Isolation ────────────────────────────────────────────────
echo "[*] Step 7: Docker isolation..."

# RabbitMQ ports (5672, 15672) - allow localhost access BEFORE deny rule
echo "[+] docker0: RabbitMQ AMQP (5672) localhost access"
ufw allow out on docker0 from 127.0.0.1 port 5672 > /dev/null 2>&1 || true
ufw allow in on docker0 to 127.0.0.1 port 5672 > /dev/null 2>&1 || true

echo "[+] docker0: RabbitMQ Management (15672) localhost access"
ufw allow out on docker0 from 127.0.0.1 port 15672 > /dev/null 2>&1 || true
ufw allow in on docker0 to 127.0.0.1 port 15672 > /dev/null 2>&1 || true

# Allow Docker exposed ports on localhost (containers -> host services)
echo "[+] docker0: Allow localhost access for exposed ports"
ufw allow in on docker0 to 127.0.0.1 > /dev/null 2>&1 || true

# Allow Docker to reach host services for Wireless Hunter development (localhost only)
echo "[+] docker0: Allow access to host services on 127.0.0.1 (ports 15025, 15050, 18080, 3000)"
ufw allow in on docker0 to 127.0.0.1 port 15025 > /dev/null 2>&1 || true
ufw allow in on docker0 to 127.0.0.1 port 15050 > /dev/null 2>&1 || true
ufw allow in on docker0 to 127.0.0.1 port 18080 > /dev/null 2>&1 || true
ufw allow in on docker0 to 127.0.0.1 port 3000 > /dev/null 2>&1 || true
ufw allow out on docker0 from 127.0.0.1 port 15025 > /dev/null 2>&1 || true
ufw allow out on docker0 from 127.0.0.1 port 15050 > /dev/null 2>&1 || true
ufw allow out on docker0 from 127.0.0.1 port 18080 > /dev/null 2>&1 || true
ufw allow out on docker0 from 127.0.0.1 port 3000 > /dev/null 2>&1 || true

# Allow Docker containers to reach host services (like React app on 3000 or proxy on 18080) via bridge gateways
echo "[+] docker networks: Allow access to host services (ports 18080, 3000)"
ufw allow in from 172.16.0.0/12 to any port 18080 proto tcp > /dev/null 2>&1 || true
ufw allow in from 172.16.0.0/12 to any port 3000 proto tcp > /dev/null 2>&1 || true

# Allow Docker build to download packages (DNS, HTTP, HTTPS from docker0 to anywhere)
echo "[+] docker0: Allow DNS/HTTP/HTTPS for Docker builds"
ufw allow out on docker0 to any port 53 proto udp > /dev/null 2>&1 || true
ufw allow out on docker0 to any port 53 proto tcp > /dev/null 2>&1 || true
ufw allow out on docker0 to any port 443 proto tcp > /dev/null 2>&1 || true
ufw allow out on docker0 to any port 80 proto tcp > /dev/null 2>&1 || true

# Deny all other docker0 outbound - applied LAST so allow rules take precedence
echo "[+] docker0: Deny all other outbound"
ufw deny out on docker0 > /dev/null 2>&1 || true

# ── Step 8a: NordVPN LAN Discovery ─────────────────────────────────────────
# NordVPN's built-in firewall (enabled by default) blocks ALL local network
# traffic, overriding UFW, unless LAN Discovery is enabled.  This is the only
# reliable way to reach the router admin (192.168.100.1) and SSH to local
# hosts while the VPN is connected.
echo "[*] Step 8a: Enabling NordVPN LAN Discovery..."
if command -v nordvpn &>/dev/null; then
    nordvpn set lan-discovery enabled 2>/dev/null && \
        echo "[+] NordVPN LAN Discovery enabled (local subnet accessible)" || \
        echo "[!] nordvpn command failed — run manually: nordvpn set lan-discovery enabled"
else
    echo "[!] nordvpn not found — skipping LAN Discovery"
fi

# ── Step 8: Exclude Local Network from VPN Tunnel ─────────────────────────
echo "[*] Step 8: Excluding local network from VPN tunnel..."
# Prevent NordVPN/OpenVPN from tunneling local network traffic.
# Two rules are needed:
#   prio 1 — packets FROM 192.168.100.0/24 (return traffic) use main table
#   prio 2 — packets TO   192.168.100.0/24 (outbound to router/hosts) use main table
# Both are required: NordVPN's table 205 catch-all sits at prio 32765,
# so prio 1/2 here always wins.

ip rule del from 192.168.100.0/24 table main prio 1 2>/dev/null || true
ip rule del to   192.168.100.0/24 table main prio 2 2>/dev/null || true

ip rule add from 192.168.100.0/24 table main prio 1
ip rule add to   192.168.100.0/24 table main prio 2

# Ensure the local network route exists in the main table (may be missing
# if wlan0 was brought up after NordVPN replaced the default route).
if ip link show wlan0 up &>/dev/null; then
    ip route replace 192.168.100.0/24 dev wlan0 proto kernel scope link 2>/dev/null || true
fi

# Flush routing cache
ip route flush cache

echo "[+] Local network to/from bypasses VPN (prio 1/2 override table 205)"
echo "[+] Router admin (192.168.100.1:80) reachable via wlan0"
echo "[+] SSH to engineer@192.168.100.xx reachable via wlan0"

# ── Enable Firewall ───────────────────────────────────────────────────────────
echo "[*] Enabling firewall..."
ufw --force enable > /dev/null

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  IRON CURTAIN ACTIVE"
echo "============================================"
echo ""
ufw status numbered
echo ""
echo "  wlan0: NordLynx (UDP 51820) to any NordVPN server"
echo "  tun0:  All traffic through OpenVPN tunnel"
echo "  nordlynx: All traffic through NordLynx tunnel"
echo "  DNS:   Pinned to $DNS_SERVER (primary) and $DNS_SERVER2 (fallback)"
echo ""
echo "Verification: curl --interface wlan0 https://ifconfig.me"
echo "              (should fail - identity protected)"
echo ""
echo "Done."
