#!/bin/bash

# ZeroTier Gateway Setup Script
# This script installs ZeroTier and configures the system as a network gateway

set -e  # Exit on any error

# =============================================================================
# CONFIGURATION VARIABLES - MODIFY THESE AS NEEDED
# =============================================================================
ZEROTIER_INTERFACE="ztaagi5gty"    # Change this to your ZeroTier interface name
ETHERNET_INTERFACE="eth0"          # Change this to your ethernet interface name
# =============================================================================

echo "Starting ZeroTier Gateway Setup..."
echo "ZeroTier Interface: $ZEROTIER_INTERFACE"
echo "Ethernet Interface: $ETHERNET_INTERFACE"
echo ""

# Step 1: Install ZeroTier
echo "Installing ZeroTier..."
DV_SAVE=$(cat /etc/debian_version)
echo buster | sudo tee /etc/debian_version >/dev/null
curl -s https://install.zerotier.com | sudo bash
echo $DV_SAVE | sudo tee /etc/debian_version >/dev/null

# Step 2: Configure iptables rules
echo "Configuring iptables rules..."
sudo iptables -t nat -A POSTROUTING -o $ZEROTIER_INTERFACE -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $ETHERNET_INTERFACE -j MASQUERADE
sudo iptables -A INPUT -i $ETHERNET_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i $ZEROTIER_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $ETHERNET_INTERFACE -o $ZEROTIER_INTERFACE -j ACCEPT
sudo iptables -A FORWARD -i $ZEROTIER_INTERFACE -o $ETHERNET_INTERFACE -j ACCEPT

# Step 3: Make iptables rules persistent via rc.local
echo "Creating persistent iptables configuration..."
sudo tee /etc/rc.local > /dev/null << EOF
#!/bin/bash
# ZeroTier Gateway iptables rules
sudo iptables -t nat -A POSTROUTING -o $ZEROTIER_INTERFACE -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $ETHERNET_INTERFACE -j MASQUERADE
sudo iptables -A INPUT -i $ETHERNET_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i $ZEROTIER_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $ETHERNET_INTERFACE -o $ZEROTIER_INTERFACE -j ACCEPT
sudo iptables -A FORWARD -i $ZEROTIER_INTERFACE -o $ETHERNET_INTERFACE -j ACCEPT
exit 0
EOF

sudo chmod +x /etc/rc.local

# Step 4: Disable AppArmor (if it interferes)
echo "Disabling AppArmor..."
sudo systemctl stop apparmor 2>/dev/null || true
sudo systemctl disable apparmor 2>/dev/null || true

# Step 5: Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

# Make IP forwarding persistent in sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Also create custom sysctl configuration
sudo tee /etc/sysctl.d/99-custom.conf > /dev/null << 'EOF'
# Enable IP forwarding for ZeroTier gateway
net.ipv4.ip_forward=1
EOF

# Apply sysctl changes
sudo sysctl -p
sudo sysctl --system

echo "ZeroTier Gateway setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Join your ZeroTier network: sudo zerotier-cli join <NETWORK_ID>"
echo "2. Authorize this device in your ZeroTier Central dashboard"
echo "3. Configure this device as a gateway in ZeroTier Central"
echo "4. Verify connectivity with: zerotier-cli info"
echo ""
echo "Note: Configured for ZeroTier interface '$ZEROTIER_INTERFACE' and Ethernet interface '$ETHERNET_INTERFACE'"
echo "If these interface names are incorrect, edit the variables at the top of this script"
