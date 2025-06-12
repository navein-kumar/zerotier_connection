---------Ubuntu------------------------------------------------------
vim /etc/sysctl.conf
#out 
net.ipv4.ip_forward = 1

sudo sysctl -p

#ip tables replace interface name

sudo iptables -t nat -A POSTROUTING -o ztliuxnmeq -j MASQUERADE 
sudo iptables -t nat -A POSTROUTING -o ens18 -j MASQUERADE 
sudo iptables -A INPUT -i ens18 -m state --state RELATED,ESTABLISHED -j ACCEPT 
sudo iptables -A INPUT -i ztliuxnmeq -m state --state RELATED,ESTABLISHED -j ACCEPT 
sudo iptables -A FORWARD -j ACCEPT

#ip tables replace interface name
sudo iptables -t nat -A POSTROUTING -o ztliuxnmeq -j MASQUERADE 
sudo iptables -A FORWARD -i ens18 -o ztliuxnmeq -m state --state RELATED,ESTABLISHED -j ACCEPT 
sudo iptables -A FORWARD -i ztliuxnmeq -o ens18 -j ACCEPT

## set persitance rule
sudo apt install iptables-persistent
sudo systemctl enable iptables
sudo iptables-save > /etc/iptables/rules.v4
----------------------end-ubuntu--------------------------------------------------



--kali-below--------------------------------------------------
---------------------step-1
echo buster | sudo tee /etc/debian_version >/dev/null
curl -s https://install.zerotier.com | sudo bash
echo $DV_SAVE | sudo tee /etc/debian_version >/dev/null
--
sudo iptables -t nat -A POSTROUTING -o ztliuubgwp -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A INPUT -i eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i ztliuubgwp -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o ztliuubgwp -j ACCEPT
sudo iptables -A FORWARD -i ztliuubgwp -o eth0 -j ACCEPT
-----step---2----perstitnace-------
save reboot 
sudo nano /etc/rc.local

#!/bin/bash
sudo iptables -t nat -A POSTROUTING -o ztliuubgwp -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A INPUT -i eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i ztliuubgwp -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o ztliuubgwp -j ACCEPT
sudo iptables -A FORWARD -i ztliuubgwp -o eth0 -j ACCEPT
exit 0

sudo chmod +x /etc/rc.local

sudo systemctl stop apparmor && sudo systemctl disable apparmor

-----step-3-----------------------
cat /proc/sys/net/ipv4/ip_forward = 1
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

sudo nano /etc/sysctl.conf
net.ipv4.ip_forward=1
sudo sysctl -p
sudo nano /etc/sysctl.d/99-custom.conf
net.ipv4.ip_forward=1
sudo sysctl --system
-------------------kali--end-----------------




------fast-direct-connect-----------------
-------------------------------------------------------------------
#tunnel only to moons
sudo iptables -A OUTPUT -p udp --dport 9993 -j DROP
sudo iptables -I OUTPUT -p udp -d 194.146.13.235 --dport 9993 -j ACCEPT
sudo apt install iptables-persistent
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent
