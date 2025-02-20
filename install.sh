#!/bin/bash

# Check if needrestart is installed and configure it to auto-restart services
if dpkg-query -W needrestart >/dev/null 2>&1; then
    sudo sed -i 's/#$nrconf{restart} = "i";/$nrconf{restart} = "a";/g' /etc/needrestart/needrestart.conf
fi

# Install iptables if not installed
echo "Checking for iptables..."
if ! command -v iptables &> /dev/null; then
    echo "iptables not found. Installing..."
    sudo apt-get install iptables -y
fi

# Get WAN interface name, filtering out loopback and virtual interfaces
INTERFACE_NAME=$(ip -o link show | awk -F': ' '!/lo|loopback/ && /UP/ {print $2; exit}')

# Validate INTERFACE_NAME
echo "Detected network interface: $INTERFACE_NAME"
if [[ -z "$INTERFACE_NAME" ]]; then
    echo "Could not automatically detect a valid network interface. Please enter it manually:"
    read INTERFACE_NAME
fi

wan_ip=$(ip -f inet -o addr show $INTERFACE_NAME | awk '{print $7}' | cut -d/ -f1)

# Get external IP
ppp1=$(ip route | awk '/default/ { print $3 }')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Ask user for allowed public IP
echo "Enter the public IP address allowed to connect to the VPN:"
read allowed_ip

# Install PPTPD
echo "Installing PPTPD..."
sudo apt-get install pptpd -y

# Ensure necessary directories exist
sudo mkdir -p /etc/ppp/
touch /etc/ppp/chap-secrets
touch /etc/ppp/pptpd-options

# Ask user for DNS settings
echo "Enter preferred primary DNS (default: 1.1.1.1):"
read dns1
dns1=${dns1:-1.1.1.1}

echo "Enter preferred secondary DNS (default: 4.2.2.4):"
read dns2
dns2=${dns2:-4.2.2.4}

# Configure DNS settings
echo "Setting DNS to $dns1 and $dns2..."
echo -e "ms-dns $dns1\nms-dns $dns2" | sudo tee /etc/ppp/pptpd-options

# Ask user for private IP configuration
echo "Enter private VPN IP range (default: 10.10.10.1):"
read private_ip
private_ip=${private_ip:-10.10.10.1}

# Configure PPTPD settings
echo "Editing PPTP Configuration..."
sudo tee /etc/pptpd.conf <<EOF
localip $private_ip
remoteip ${private_ip}10-200
EOF

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.conf
sudo sysctl -p

# Configure firewall rules
echo "Configuring Firewall..."
sudo iptables -t nat -A POSTROUTING -o $INTERFACE_NAME -j MASQUERADE
sudo iptables -A INPUT -s $allowed_ip -i ppp0 -j ACCEPT
sudo iptables -A FORWARD -i $INTERFACE_NAME -j ACCEPT

# Ask for VPN username and password
echo "Set VPN username:"
read username
echo "Set VPN password:"
read password
echo "$username * $password *" | sudo tee /etc/ppp/chap-secrets

# Restart PPTPD service
echo "Restarting PPTP service..."
sudo service pptpd restart

echo "All done! Use the following commands to manage your VPN service:"
echo " - Check status: sudo systemctl status pptpd"
echo " - Restart service: sudo systemctl restart pptpd"
echo " - Enable service on boot: sudo systemctl enable pptpd"
