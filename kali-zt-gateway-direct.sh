#!/bin/bash
set -e

# =============================================================================
# DIRECT MODE - Client gives full internet access via eth1
# No eth0 needed - eth1 handles everything
# =============================================================================
ZEROTIER_INTERFACE="zttwh34l4w"
CLIENT_INTERFACE="eth1"
BLACKLIST_INTERFACES="docker"
# =============================================================================

echo "================================================"
echo "   ZeroTier VAPT Gateway - DIRECT MODE"
echo "================================================"
echo "    ZT Interface    : $ZEROTIER_INTERFACE"
echo "    Client Interface: $CLIENT_INTERFACE"
echo "    ZT Blacklist    : $BLACKLIST_INTERFACES"
echo ""

# =============================================================================
# PRE-CHECK 1: iptables backend
# =============================================================================
echo "[*] Pre-Check 1: Verifying iptables..."
if ! command -v iptables &> /dev/null; then
    echo "    iptables not found - installing..."
    sudo apt update -y > /dev/null
    sudo apt install iptables -y > /dev/null
    echo "    Installed"
fi

IPTABLES_VERSION=$(sudo iptables -V 2>/dev/null)
if echo "$IPTABLES_VERSION" | grep -q "nf_tables"; then
    echo "    nf_tables detected - switching to legacy..."
    sudo apt install iptables -y > /dev/null 2>&1
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    echo "    Switched to iptables-legacy"
else
    echo "    iptables OK: $IPTABLES_VERSION"
fi

# =============================================================================
# PRE-CHECK 2: Disable UFW
# =============================================================================
echo "[*] Pre-Check 2: Checking UFW..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | grep -i "Status:" | awk '{print $2}')
    if [ "$UFW_STATUS" == "active" ]; then
        echo "    UFW active - disabling..."
        sudo ufw disable
        sudo systemctl stop ufw 2>/dev/null || true
        sudo systemctl disable ufw 2>/dev/null || true
        echo "    UFW disabled"
    else
        echo "    UFW already inactive"
    fi
else
    echo "    UFW not installed - skipping"
fi

# =============================================================================
# PRE-CHECK 3: Disable firewalld
# =============================================================================
echo "[*] Pre-Check 3: Checking firewalld..."
if command -v firewall-cmd &> /dev/null; then
    if sudo systemctl is-active firewalld &>/dev/null; then
        echo "    firewalld active - disabling..."
        sudo systemctl stop firewalld
        sudo systemctl disable firewalld
        echo "    firewalld disabled"
    else
        echo "    firewalld already inactive"
    fi
else
    echo "    firewalld not installed - skipping"
fi
echo ""

# =============================================================================
# STEP 1: IP Forwarding
# =============================================================================
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

# =============================================================================
# STEP 2: Flush iptables
# =============================================================================
echo "[*] Step 2: Flushing iptables..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
echo "    Done"

# =============================================================================
# STEP 3: Default ACCEPT policies
# =============================================================================
echo "[*] Step 3: Setting policies to ACCEPT..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
echo "    Done"

# =============================================================================
# STEP 4: MASQUERADE on eth1 only
# =============================================================================
echo "[*] Step 4: Applying MASQUERADE..."
sudo iptables -t nat -A POSTROUTING -o $CLIENT_INTERFACE -j MASQUERADE
echo "    MASQUERADE: $CLIENT_INTERFACE only"

# =============================================================================
# STEP 5: Routes - remove eth0, eth1 handles everything
# =============================================================================
echo "[*] Step 5: Configuring routes..."
sudo ip route del default dev eth0 2>/dev/null || true
ETH1_GW=$(ip route show dev $CLIENT_INTERFACE | grep -oE 'via [0-9.]+' | awk '{print $2}' | head -1)
sudo ip route del default dev $CLIENT_INTERFACE 2>/dev/null || true
[ -n "$ETH1_GW" ] && sudo ip route add default via $ETH1_GW dev $CLIENT_INTERFACE metric 10
echo "    eth0 default route removed"
echo "    eth1 metric=10 (internet + client network)"

# =============================================================================
# STEP 6: ZeroTier blacklist
# =============================================================================
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

# =============================================================================
# STEP 7: Save iptables rules
# =============================================================================
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
EOF
sudo chmod +x /etc/iptables-vapt-rules.sh
echo "    Saved to /etc/iptables-vapt-rules.sh"

# =============================================================================
# STEP 8: Systemd service
# =============================================================================
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
echo "    Service enabled"

# =============================================================================
# STEP 9: Restart ZeroTier
# =============================================================================
echo "[*] Step 9: Restarting ZeroTier..."
sudo systemctl restart zerotier-one
sleep 5
echo "    Done"

# =============================================================================
# STEP 10: Verify
# =============================================================================
echo ""
echo "================================================"
echo "[+] DIRECT MODE Setup Complete"
echo "================================================"
echo "--- Policies ---"
sudo iptables -L | grep -E "Chain|policy"
echo ""
echo "--- NAT Rules ---"
sudo iptables -t nat -L POSTROUTING -n -v
echo ""
echo "--- Routes ---"
ip route show
echo ""
echo "--- IP Forwarding ---"
cat /proc/sys/net/ipv4/ip_forward
echo ""
echo "--- ZeroTier local.conf ---"
cat /var/lib/zerotier-one/local.conf
echo ""
echo "--- ZeroTier Peers ---"
sudo zerotier-cli listpeers
echo ""
echo "================================================"
echo "[+] LHOST (eth1)    : $(ip addr show $CLIENT_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "[+] ZeroTier IP     : $(ip addr show $ZEROTIER_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "[+] Internet via    : $CLIENT_INTERFACE (client provided)"
echo "================================================"
