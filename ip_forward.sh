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

#tunnel only to moons
sudo iptables -A OUTPUT -p udp --dport 9993 -j DROP
sudo iptables -I OUTPUT -p udp -d 194.146.13.235 --dport 9993 -j ACCEPT
sudo apt install iptables-persistent
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent
