#!/bin/bash

# Check if needrestart is installed and configure it
dpkg-query -W needrestart >/dev/null 2>&1 && \
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf

# Get the WAN interface name
INTERFACE_NAME=$(ip a | awk '/state UP/ {print $2}' | tr -d ':')
if [[ $INTERFACE_NAME == *"w"* ]]; then
    # WLAN connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME | cut -d\  -f 7 | cut -d/ -f 1)
else
    # Ethernet connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME | cut -d\  -f 7 | cut -d/ -f 1)
fi

ppp1=$(/sbin/ip route | awk '/default/ { print $3 }')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Installing PPTPD
echo "Installing PPTPD"
sudo apt-get install pptpd -y

# Set Secure DNS Servers
echo "Setting Secure DNS Servers"
echo "ms-dns 1.1.1.1" | sudo tee -a /etc/ppp/pptpd-options
echo "ms-dns 9.9.9.9" | sudo tee -a /etc/ppp/pptpd-options

# Edit PPTP Configuration
echo "Editing PPTP Configuration"
echo "localip 10.10.10.1" | sudo tee -a /etc/pptpd.conf
echo "remoteip 10.10.10.100-200" | sudo tee -a /etc/pptpd.conf

# Enable IP forwarding
echo "Enabling IP forwarding"
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure Firewall
echo "Configuring Firewall"
sudo iptables -t nat -A POSTROUTING -o $INTERFACE_NAME -j MASQUERADE && iptables-save
sudo iptables --table nat --append POSTROUTING --out-interface ppp0 -j MASQUERADE
sudo iptables -I INPUT -i ppp0 -j DROP  # Block all by default

# Ask user for allowed IPs
echo "Enter the IPs that should be allowed to connect (comma-separated, e.g., 192.168.1.10,203.0.113.5):"
read allowed_ips
IFS=',' read -ra ADDR <<< "$allowed_ips"
for ip in "${ADDR[@]}"; do
    sudo iptables -I INPUT -s $ip -i ppp0 -j ACCEPT
    echo "Allowing $ip"
done

clear

# Adding VPN Users
echo "Set username:"
read username
echo "Set Password:"
read -s password
echo "$username * $password *" | sudo tee -a /etc/ppp/chap-secrets

# Restarting PPTP service
echo "Restarting PPTP service"
sudo service pptpd restart

echo "All done!"
echo "Useful commands:"
echo "- Restart service: sudo service pptpd restart"
echo "- Check status: sudo service pptpd status"
echo "- View logs: sudo journalctl -u pptpd"
