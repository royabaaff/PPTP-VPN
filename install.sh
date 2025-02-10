#!/bin/bash
set -e

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check if needrestart is installed and configure it to auto-restart services
if dpkg-query -W needrestart >/dev/null 2>&1; then
    echo "Configuring needrestart..."
    if [ -f /etc/needrestart/needrestart.conf ]; then
        sudo sed -i 's/#$nrconf{restart} = '\''i'\'';/$nrconf{restart} = '\''a'\'';/g' /etc/needrestart/needrestart.conf
    else
        echo "File /etc/needrestart/needrestart.conf not found. Creating it..."
        sudo mkdir -p /etc/needrestart
        sudo tee /etc/needrestart/needrestart.conf <<EOF
# Configuration for needrestart
\$nrconf{restart} = 'a';
EOF
    fi
else
    echo "needrestart is not installed. Skipping configuration."
fi

# Get WAN interface name
INTERFACE_NAME=$(ip a | awk '/state UP/ {print $2}' | tr -d ':')
wan_ip=$(ip -f inet -o addr show $INTERFACE_NAME | awk '{print $7}' | cut -d/ -f1)

# Get external IP
ppp1=$(ip route show default | awk '{print $3}')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Ask for private IP range with a default suggestion
echo "Please enter the private IP range for VPN clients (e.g., 10.10.10)."
echo "This will determine the range of IPs assigned to connected clients."
read -p "Enter private IP range (default: 10.10.10): " private_ip
private_ip=${private_ip:-10.10.10}

# Ask for DNS servers with a default suggestion
read -p "Use default DNS (1.1.1.1, 9.9.9.9)? (y/n): " use_default_dns
if [[ "$use_default_dns" =~ ^[Yy]$ ]]; then
    dns1="1.1.1.1"
    dns2="9.9.9.9"
else
    read -p "Enter primary DNS: " dns1
    read -p "Enter secondary DNS: " dns2
fi

# Ask for allowed client IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

read -p "Enter allowed client IP (only this IP will be able to connect): " allowed_ip
while ! validate_ip "$allowed_ip"; do
    read -p "Invalid IP. Please enter a valid IP: " allowed_ip
done

# Install PPTPD
echo "Installing PPTPD..."
if sudo apt-get install pptpd -y; then
    echo "PPTPD installed successfully."
else
    echo "Failed to install PPTPD. Exiting..."
    exit 1
fi

# Configure DNS settings
echo "Configuring DNS..."
echo -e "ms-dns $dns1\nms-dns $dns2" | sudo tee -a /etc/ppp/pptpd-options

# Configure PPTPD settings
echo "Configuring PPTP server..."
sudo tee /etc/pptpd.conf <<EOF
localip $ppp1
remoteip ${private_ip}.10-200
EOF

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure firewall rules
echo "Configuring firewall rules..."
sudo iptables -t nat -A POSTROUTING -o $INTERFACE_NAME -j MASQUERADE
sudo iptables -A INPUT -s $allowed_ip -i ppp0 -j ACCEPT
sudo iptables -A FORWARD -i $INTERFACE_NAME -j ACCEPT

# Save firewall rules
echo "Saving firewall rules..."
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

# Ask for VPN username and password
echo "Set VPN username:"
read username
echo "Set VPN password:"
read password
echo "$username * $password *" | sudo tee -a /etc/ppp/chap-secrets

# Restart PPTP service
echo "Restarting PPTP service..."
sudo systemctl restart pptpd
if sudo systemctl is-active --quiet pptpd; then
    echo "PPTPD is running successfully."
else
    echo "Failed to start PPTPD. Please check the logs."
    exit 1
fi

# Final instructions
echo "PPTP VPN setup completed!"
echo "Use the following commands to manage the service:"
echo "Check status: sudo systemctl status pptpd"
echo "Restart service: sudo systemctl restart pptpd"
echo "Enable service on boot: sudo systemctl enable pptpd"
