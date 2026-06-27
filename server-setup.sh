#!/usr/bin/env bash
#
# WireGuard VPN server setup for Ubuntu/Debian.
# Run this ON YOUR US CLOUD SERVER as root (or with sudo).
#
#   sudo bash server-setup.sh
#
# It installs WireGuard, generates server + client keys, enables routing/NAT,
# opens the firewall, starts the service on boot, and writes a ready-to-use
# Mac client config to ./client-mac.conf
#
set -euo pipefail

# ---- settings (change only if you have a reason to) -------------------------
WG_IF="wg0"
WG_PORT="51820"            # UDP port the server listens on
WG_SUBNET="10.8.0"        # VPN internal network -> server .1, mac .2
CLIENT_DNS="1.1.1.1"      # DNS the Mac uses while connected
CLIENT_OUT="client-mac.conf"
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash server-setup.sh" >&2
  exit 1
fi

echo "==> Installing WireGuard..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y wireguard iptables curl >/dev/null

echo "==> Detecting public IP and network interface..."
PUB_IP="$(curl -4 -s --max-time 10 ifconfig.me || true)"
[[ -z "$PUB_IP" ]] && PUB_IP="$(curl -4 -s --max-time 10 https://api.ipify.org || true)"
if [[ -z "$PUB_IP" ]]; then
  read -rp "Could not auto-detect public IP. Enter your server's public IP: " PUB_IP
fi
# default route interface, used for NAT (e.g. eth0, ens3...)
NET_IF="$(ip -4 route ls | awk '/default/ {print $5; exit}')"
echo "    public IP : $PUB_IP"
echo "    interface : $NET_IF"

echo "==> Enabling IP forwarding..."
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-wireguard.conf
sysctl -q -p /etc/sysctl.d/99-wireguard.conf

echo "==> Generating keys..."
umask 077
SERVER_PRIV="$(wg genkey)"
SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"
CLIENT_PRIV="$(wg genkey)"
CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"

echo "==> Writing /etc/wireguard/${WG_IF}.conf ..."
cat > "/etc/wireguard/${WG_IF}.conf" <<EOF
[Interface]
Address = ${WG_SUBNET}.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
PostUp   = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; iptables -D FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IF} -j MASQUERADE

# --- Mac client ---
[Peer]
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${WG_SUBNET}.2/32
EOF
chmod 600 "/etc/wireguard/${WG_IF}.conf"

echo "==> Opening firewall (UDP ${WG_PORT})..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${WG_PORT}/udp" >/dev/null 2>&1 || true
fi

echo "==> Starting WireGuard and enabling on boot..."
systemctl enable "wg-quick@${WG_IF}" >/dev/null 2>&1
systemctl restart "wg-quick@${WG_IF}"

echo "==> Writing Mac client config -> ${CLIENT_OUT}"
cat > "${CLIENT_OUT}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${WG_SUBNET}.2/24
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${PUB_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 "${CLIENT_OUT}"

echo
echo "============================================================"
echo " DONE. WireGuard is running and will auto-start on reboot."
echo
echo " IMPORTANT: in your cloud provider's firewall / security"
echo " group, allow inbound  UDP ${WG_PORT}  to this server."
echo
echo " Your Mac config is below (also saved to ${CLIENT_OUT}):"
echo "------------------------------------------------------------"
cat "${CLIENT_OUT}"
echo "------------------------------------------------------------"
echo " Copy that into the WireGuard app on your Mac and toggle ON."
echo "============================================================"
