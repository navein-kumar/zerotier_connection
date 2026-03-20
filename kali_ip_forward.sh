#!/bin/bash
set -e

# =============================================================================
# CONFIGURATION VARIABLES - EDIT THESE AS NEEDED
# =============================================================================
ZEROTIER_INTERFACE="zttwh34l4w"       # ZeroTier virtual interface
ZT_NAT_INTERFACE="eth0"               # NAT adapter (ZeroTier internet path)
CLIENT_INTERFACE="eth1"               # Bridged adapter (client network)
BLACKLIST_INTERFACES="eth1,docker"    # Comma-separated interfaces to block from ZeroTier
# =============================================================================

echo "[*] ZeroTier VAPT Gateway Setup - FULL OPEN MODE"
echo "    ZT Interface    : $ZEROTIER_INTERFACE"
echo "    NAT Interface   : $ZT_NAT_INTERFACE"
echo "    Client Interface: $CLIENT_INTERFACE"
echo "    ZT Blacklist    : $BLACKLIST_INTERFACES"
echo ""

# Step 1: IP Forwarding
echo "[*] Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi
sudo tee /etc/sysctl.d/99-zerotier-gw.conf > /dev/null << 'EOF'
net.ipv4.ip_forward=1
EOF
sudo sysctl -p
sudo sysctl --system

# Step 2: Flush all existing rules
echo "[*] Flushing existing iptables rules..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Step 3: Set default policies to ACCEPT
echo "[*] Setting default policies to ACCEPT..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Step 4: MASQUERADE for routing
echo "[*] Applying MASQUERADE rules..."
sudo iptables -t nat -A POSTROUTING -o $CLIENT_INTERFACE -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $ZT_NAT_INTERFACE -j MASQUERADE

# Step 5: ZeroTier local.conf - build blacklist from variable
echo "[*] Configuring ZeroTier interface blacklist..."

# Convert comma-separated string to JSON array
# e.g. "eth1,docker" -> ["eth1","docker"]
IFS=',' read -ra BL_ARRAY <<< "$BLACKLIST_INTERFACES"
JSON_ARRAY=$(printf '"%s",' "${BL_ARRAY[@]}" | sed 's/,$//')

sudo tee /var/lib/zerotier-one/local.conf > /dev/null << EOF
{
  "settings": {
    "interfacePrefixBlacklist": [$JSON_ARRAY]
  }
}
EOF

echo "    ZT local.conf written: [$JSON_ARRAY]"

# Step 6: Save iptables rules script
echo "[*] Creating iptables rules script..."
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

# Step 7: Create systemd service
echo "[*] Creating systemd persistence service..."
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

# Step 8: Restart ZeroTier
echo "[*] Restarting ZeroTier..."
sudo systemctl restart zerotier-one
sleep 5

# Step 9: Verify
echo ""
echo "[+] Setup Complete! Verification:"
echo "--- Default Policies ---"
sudo iptables -L | grep -E "Chain|policy"
echo "--- NAT Rules ---"
sudo iptables -t nat -L POSTROUTING -n -v
echo "--- IP Forwarding ---"
cat /proc/sys/net/ipv4/ip_forward
echo "--- ZeroTier local.conf ---"
cat /var/lib/zerotier-one/local.conf
echo "--- ZeroTier Peers ---"
sudo zerotier-cli listpeers
echo ""
echo "[+] LHOST (eth1) : $(ip addr show $CLIENT_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "[+] ZeroTier IP  : $(ip addr show $ZEROTIER_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
