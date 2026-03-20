#!/bin/bash
set -e

# =============================================================================
# NAT MODE - Client gives internal access only
# Kali uses eth0 for internet (ZeroTier path)
# =============================================================================
ZEROTIER_INTERFACE="zttwh34l4w"
ZT_NAT_INTERFACE="eth0"
CLIENT_INTERFACE="eth1"
BLACKLIST_INTERFACES="eth1,docker"
# =============================================================================

echo "[*] ZeroTier VAPT Gateway - NAT MODE"
echo "    ZT Interface    : $ZEROTIER_INTERFACE"
echo "    NAT Interface   : $ZT_NAT_INTERFACE"
echo "    Client Interface: $CLIENT_INTERFACE"
echo "    ZT Blacklist    : $BLACKLIST_INTERFACES"
echo ""

# Step 1: IP Forwarding
echo "[*] Step 1: Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi
sudo tee /etc/sysctl.d/99-zerotier-gw.conf > /dev/null << 'EOF'
net.ipv4.ip_forward=1
EOF
sudo sysctl -p > /dev/null
sudo sysctl --system > /dev/null
echo "    Done"

# Step 2: Flush iptables
echo "[*] Step 2: Flushing iptables..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
echo "    Done"

# Step 3: Default ACCEPT policies
echo "[*] Step 3: Setting policies to ACCEPT..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
echo "    Done"

# Step 4: MASQUERADE on both interfaces
echo "[*] Step 4: Applying MASQUERADE..."
sudo iptables -t nat -A POSTROUTING -o $CLIENT_INTERFACE -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $ZT_NAT_INTERFACE -j MASQUERADE
echo "    MASQUERADE: $CLIENT_INTERFACE + $ZT_NAT_INTERFACE"

# Step 5: Routes - eth0 preferred for ZeroTier
echo "[*] Step 5: Configuring routes..."
ETH0_GW=$(ip route show dev $ZT_NAT_INTERFACE | grep -oE 'via [0-9.]+' | awk '{print $2}' | head -1)
ETH1_GW=$(ip route show dev $CLIENT_INTERFACE | grep -oE 'via [0-9.]+' | awk '{print $2}' | head -1)
sudo ip route del default dev $ZT_NAT_INTERFACE 2>/dev/null || true
sudo ip route del default dev $CLIENT_INTERFACE 2>/dev/null || true
[ -n "$ETH0_GW" ] && sudo ip route add default via $ETH0_GW dev $ZT_NAT_INTERFACE metric 10
[ -n "$ETH1_GW" ] && sudo ip route add default via $ETH1_GW dev $CLIENT_INTERFACE metric 100
echo "    eth0 metric=10  (ZeroTier internet)"
echo "    eth1 metric=100 (client network)"

# Step 6: ZeroTier blacklist
echo "[*] Step 6: Configuring ZeroTier blacklist..."
IFS=',' read -ra BL_ARRAY <<< "$BLACKLIST_INTERFACES"
JSON_ARRAY=$(printf '"%s",' "${BL_ARRAY[@]}" | sed 's/,$//')
sudo tee /var/lib/zerotier-one/local.conf > /dev/null << EOF
{
  "settings": {
    "interfacePrefixBlacklist": [$JSON_ARRAY]
  }
}
EOF
echo "    Written: [$JSON_ARRAY]"

# Step 7: Save iptables rules
echo "[*] Step 7: Saving iptables rules..."
sudo tee /etc/iptables-vapt-rules.sh > /dev/null << EOF
#!/bin/bash
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -A POSTROUTING -o $CLIENT_INTERFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -o $ZT_NAT_INTERFACE -j MASQUERADE
EOF
sudo chmod +x /etc/iptables-vapt-rules.sh
echo "    Saved"

# Step 8: Systemd service
echo "[*] Step 8: Creating systemd service..."
sudo tee /etc/systemd/system/iptables-vapt.service > /dev/null << EOF
[Unit]
Description=VAPT ZeroTier Gateway iptables Rules
After=network.target zerotier-one.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /etc/iptables-vapt-rules.sh

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable iptables-vapt.service
echo "    Enabled"

# Step 9: Restart ZeroTier
echo "[*] Step 9: Restarting ZeroTier..."
sudo systemctl restart zerotier-one
sleep 5
echo "    Done"

# Step 10: Verify
echo ""
echo "================================================"
echo "[+] NAT MODE Setup Complete"
echo "================================================"
echo "--- Policies ---"
sudo iptables -L | grep -E "Chain|policy"
echo "--- NAT Rules ---"
sudo iptables -t nat -L POSTROUTING -n -v
echo "--- Routes ---"
ip route show
echo "--- IP Forwarding ---"
cat /proc/sys/net/ipv4/ip_forward
echo "--- ZeroTier local.conf ---"
cat /var/lib/zerotier-one/local.conf
echo "--- ZeroTier Peers ---"
sudo zerotier-cli listpeers
echo ""
echo "[+] LHOST (eth1)  : $(ip addr show $CLIENT_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "[+] ZeroTier IP   : $(ip addr show $ZEROTIER_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "[+] NAT via       : $ZT_NAT_INTERFACE"
echo "================================================"
