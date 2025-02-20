#/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi
sudo apt update
# create user to connect
sudo useradd -m -p $(openssl passwd -1 'ZeroTierpass123') zerotier && sudo usermod -aG sudo zerotier

# Check if SSH is installed
if ! command -v ssh &> /dev/null; then
  echo "SSH is not installed. Installing SSH..."
  sudo apt update
  sudo apt install openssh-server -y
else
  echo "SSH is already installed."
fi

# Check if SSH service is running
if ! sudo systemctl is-active --quiet ssh; then
  echo "SSH service is not running. Starting SSH..."
  sudo systemctl start ssh
else
  echo "SSH service is already running."
fi

# Enable SSH to start on boot
if ! sudo systemctl is-enabled --quiet ssh; then
  echo "Enabling SSH to start on boot..."
  sudo systemctl enable ssh
else
  echo "SSH is already enabled to start on boot."
fi

# Check SSH status
sudo systemctl status ssh
#disable ufw
ufw disable

sudo apt install curl -y

#install zerotier
curl -s https://install.zerotier.com | sudo bash
#join zerotier network
zerotier-cli join 147d0d4e547bfec4
zerotier-cli info
