#!/bin/bash

# چک کردن اینکه نیاز به رستارت هست یا نه
if dpkg-query -W needrestart >/dev/null 2>&1; then
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
fi

# گرفتن نام اینترفیس WAN
INTERFACE_NAME=$(ip a | awk '/state UP/ {print $2}' | tr -d ':')
wan_ip=$(ip -f inet -o addr show $INTERFACE_NAME | awk '{print $7}' | cut -d/ -f1)

# گرفتن IP خارجی
ppp1=$(ip route | awk '/default/ { print $3 }')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# نصب pptpd
echo "Installing PPTPD"
sudo apt-get install pptpd -y

# تنظیم DNS گوگل
echo "Setting Google DNS"
echo -e "ms-dns 8.8.8.8\nms-dns 8.8.4.4" | sudo tee -a /etc/ppp/pptpd-options

# تنظیمات PPTP
echo "Editing PPTP Configuration"
sudo tee -a /etc/pptpd.conf <<EOF
localip $ppp1
remoteip ${ppp1}0-200
EOF

# فعال‌سازی IP forwarding
echo "Enabling IP forwarding"
sudo tee -a /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sudo sysctl -p

# پیکربندی فایروال
echo "Configuring Firewall"
sudo iptables -t nat -A POSTROUTING -o $INTERFACE_NAME -j MASQUERADE
sudo iptables -A INPUT -s $ip/8 -i ppp0 -j ACCEPT
sudo iptables -A FORWARD -i $INTERFACE_NAME -j ACCEPT

# درخواست نام کاربری و پسورد برای VPN
echo "Set username:"
read username
echo "Set password:"
read password
echo "$username * $password *" | sudo tee -a /etc/ppp/chap-secrets

# ریستارت کردن سرویس pptpd
echo "Restarting PPTP service"
sudo service pptpd restart

echo "All done!"
