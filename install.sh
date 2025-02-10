#!/bin/bash

if dpkg-query -W needrestart >/dev/null 2>&1; then
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
fi

# Get the interface name for the WAN connection using ip a command
INTERFACE_NAME=$(ip a | awk '/state UP/ {print $2}' | tr -d ':')
if [[ $INTERFACE_NAME == *"w"* ]]
then
    # WLAN connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME|cut -d\  -f 7 | cut -d/ -f 1)
else
    # Ethernet connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME|cut -d\  -f 7 | cut -d/ -f 1)
fi

ppp1=$(/sbin/ip route | awk '/default/ { print $3 }')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Installing pptpd
echo "Installing PPTPD"
sudo apt-get install pptpd -y

# Set DNS (Secure defaults with option to customize)
echo "Enter preferred DNS servers (or press Enter for default: 1.1.1.1, 9.9.9.9):"
read custom_dns
if [ -z "$custom_dns" ]; then
    custom_dns="1.1.1.1 9.9.9.9"
fi
echo "Using DNS: $custom_dns"
echo "ms-dns $custom_dns" | sudo tee -a /etc/ppp/pptpd-options

# Edit PPTP Configuration
echo "Editing PPTP Configuration"
echo "localip 10.10.10.1" | sudo tee -a /etc/pptpd.conf
echo "remoteip 10.10.10.10-100" | sudo tee -a /etc/pptpd.conf

# Enabling IP forwarding
echo "Enabling IP forwarding"
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure Allowed IPs (Whitelisting)
echo "Enter the IPs that should be allowed to connect (comma-separated, e.g., 192.168.1.10,203.0.113.5), or press Enter for default (10.10.10.0/24):"
read allowed_ips
if [ -z "$allowed_ips" ]; then
    allowed_ips="10.10.10.0/24"
fi
echo "Allowed IPs: $allowed_ips"
for ip in $(echo $allowed_ips | tr ',' ' '); do
    sudo iptables -I INPUT -s $ip -p tcp --dport 1723 -j ACCEPT
    sudo iptables -I INPUT -s $ip -p gre -j ACCEPT
    sudo iptables -I FORWARD -s $ip -j ACCEPT
done

clear

# Adding VPN Users
echo "Set username:"
read username
echo "Set Password:"
read password
echo "$username * $password *" | sudo tee -a /etc/ppp/chap-secrets

# Restarting Service 
sudo service pptpd restart

echo "All done! Use the following commands to manage the service:"
echo "Restart VPN: sudo service pptpd restart"
echo "Check status: sudo service pptpd status"
echo "Stop VPN: sudo service pptpd stop"
