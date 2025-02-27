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
--
