#!/bin/bash

# Default IP Range
DEFAULT_LOCAL_IP="10.10.10.1"
DEFAULT_REMOTE_IP="10.10.10.100-200"

echo "Enter the local IP (press Enter to use default: $DEFAULT_LOCAL_IP):"
read LOCAL_IP
LOCAL_IP=${LOCAL_IP:-$DEFAULT_LOCAL_IP}

echo "Enter the remote IP range (press Enter to use default: $DEFAULT_REMOTE_IP):"
read REMOTE_IP
REMOTE_IP=${REMOTE_IP:-$DEFAULT_REMOTE_IP}

echo "Configuring VPN with local IP: $LOCAL_IP and remote IP range: $REMOTE_IP"

# Apply configuration
cat <<EOF > /etc/ppp/options.pptpd
localip $LOCAL_IP
remoteip $REMOTE_IP
EOF

# Enable IP Forwarding
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
sysctl -p

# Restart PPTP Service
systemctl restart pptpd

echo "VPN setup completed successfully!"
echo "To restart service: systemctl restart pptpd"
echo "To check status: systemctl status pptpd"
