#!/bin/bash

# Close if any error
set -e
# Update
echo
echo "=== Updating package lists and upgrading system ==="
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" upgrade -y
echo "Done"

# Requesting variables from the user before starting
# SSH-port
echo
echo "=== SSH-port Setup ==="
# Find actual active SSH-port from config SSH (find row ^Port)
CURRENT_PORT=$(awk '/^Port / {print $2}' /etc/ssh/sshd_config || echo "22")
# If row not finded, by default think, that SSH-port is 22
if [ -z "$CURRENT_PORT" ]; then CURRENT_PORT=22; fi
# If SSH-port already custom (not 22)
if [ "$CURRENT_PORT" -ne 22 ]; then
    while true; do
        echo "Your SSH-port: $CURRENT_PORT. Do you want to change it? (y/n) (Default: n)"
        read -p "Your choice: " CHANGE_INPUT
        # If pressed Enter — write "n" and set SSH-port
        if [ -z "$CHANGE_INPUT" ]; then
            CHANGE_INPUT="n"
            echo -e "\e[1A\e[KYour choice: n"
        fi
        # Check input
        if [ "${CHANGE_INPUT,,}" = "n" ] || [ "${CHANGE_INPUT,,}" = "no" ]; then
            SSH_PORT=$CURRENT_PORT
            echo "Keeping current port: $SSH_PORT"
            SSH_SKIP=true
            break
        elif [ "${CHANGE_INPUT,,}" = "y" ] || [ "${CHANGE_INPUT,,}" = "yes" ]; then
            echo "Proceeding to change the port..."
            break
        else
            # Trash talk
            echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
        fi
    done
fi
# If SSH-port was 22, or user accept change his custom port
if [ "$SSH_SKIP" != true ]; then
  echo "Enter SSH-port"
  echo "  - Empty (press Enter) to use the default SSH-port (22)"
  echo "  - Enter 'r' to generate a random SSH-port (45000-65535)"
  echo "  - Or enter your custom SSH-port number (from 1 to 65535)"
  read -p "Your choice: " SSH_INPUT
  if [ -z "$SSH_INPUT" ]; then
    SSH_PORT=22
    echo "Выбран дефолтный порт: $SSH_PORT"
  elif [ "${SSH_INPUT,,}" = "r" ] || [ "${SSH_INPUT,,}" = "rand" ] || [ "${SSH_INPUT,,}" = "random" ]; then
    # Generate random number in 45000-65535
    SSH_PORT=$((RANDOM % 20536 + 45000))
    echo "Your SSH-port: $SSH_PORT"
  else
    # Check allowed number
    if [[ "$SSH_INPUT" =~ ^[0-9]+$ ]] && [ "$SSH_INPUT" -ge 1 ] && [ "$SSH_INPUT" -le 65535 ]; then
      SSH_PORT=$SSH_INPUT
      echo "Your SSH-port: $SSH_PORT"
    else
      echo -e "Error: format or port number not allowed (1-65535).\n Your SSH-port: 22\n"
      SSH_PORT=22
    fi
  fi
fi

# Swapfile 2gb
echo
echo "=== Swapfile Setup ==="
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
    echo "Swapfile exist, skip creating."
    echo
fi
free -h

# DNS over TLS
echo
echo "=== DNS over TLS (DoT) Setup ==="
while true; do
    echo "Do you want to enable DNS over TLS (DoT)? (y/n) (Default: y)"
    read -p "Your choice: " DOT_INPUT
    if [ -z "$DOT_INPUT" ]; then
        DOT_INPUT="y"
        echo -e "\e[1A\e[KYour choice: y"
    fi
    if [ "${DOT_INPUT,,}" = "y" ] || [ "${DOT_INPUT,,}" = "yes" ]; then
        ENABLE_DOT=true
        echo "Proceeding to configure DNS over TLS..."
        break
    elif [ "${DOT_INPUT,,}" = "n" ] || [ "${DOT_INPUT,,}" = "no" ]; then
        ENABLE_DOT=false
        echo "Skipping DNS over TLS setup."
        break
    else
        echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
    fi
done
if [ "$ENABLE_DOT" = true ]; then
    while true; do
        echo
        echo "Select DNS provider:"
        echo "  1) Quad9 (Privacy) [Default]"
        echo "  2) Cloudflare (Speed)"
        echo "  3) Google (Stability)"
        echo "  4) Yandex (RU segment)"
        echo "  5) Google + Cloudflare (Max Stability & Speed)"
        echo "  6) Quad9 + Cloudflare (Max Privacy & Speed)"
        read -p "Your choice (1-6): " DNS_CHOICE
        if [ -z "$DNS_CHOICE" ]; then
            DNS_CHOICE="1"
            echo -e "\e[1A\e[KYour choice (1-6): 1"
        fi
        DNSSEC_POLICY="yes"
        case "$DNS_CHOICE" in
            1)
                DNS_SERVERS="9.9.9.9 149.112.112.112"
                PROVIDER_NAME="Quad9"
                break
                ;;
            2)
                DNS_SERVERS="1.1.1.1 1.0.0.1"
                PROVIDER_NAME="Cloudflare"
                break
                ;;
            3)
                DNS_SERVERS="8.8.8.8 8.8.4.4"
                PROVIDER_NAME="Google"
                break
                ;;
            4)
                DNS_SERVERS="77.88.8.8 77.88.8.1"
                PROVIDER_NAME="Yandex"
                DNSSEC_POLICY="allow-downgrade"
                break
                ;;
            5)
                DNS_SERVERS="8.8.8.8 1.1.1.1 8.8.4.4 1.0.0.1"
                PROVIDER_NAME="Google + Cloudflare"
                break
                ;;
            6)
                DNS_SERVERS="9.9.9.9 1.1.1.1 149.112.112.112 1.0.0.1"
                PROVIDER_NAME="Quad9 + Cloudflare"
                break
                ;;
            *)
                echo "Error: Invalid choice. Please enter a number between 1 and 6."
                ;;
        esac
    done
    echo "Configuring $PROVIDER_NAME DNS over TLS (DNSSEC: $DNSSEC_POLICY)..."
    sudo rm -f /etc/systemd/resolved.conf.d/*.conf || true
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/dot-custom.conf > /dev/null <<EOT
[Resolve]
DNS=$DNS_SERVERS
Domains=~.
DNSOverTLS=yes
DNSSEC=$DNSSEC_POLICY
EOT
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    sudo systemctl daemon-reload
    sudo systemctl restart systemd-resolved
    NET_INT=$(ip route | grep default | awk '{print $5}')
    if [ -n "$NET_INT" ]; then
        sudo resolvectl dns "$NET_INT" ""
        sudo resolvectl domain "$NET_INT" ""
    fi
    resolvectl status
fi

# SSH && UFW
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
# UFW No Ping
echo
echo "=== NoPing in UFW Setup ==="
# Change ACCEPT to DROP for all rules INPUT and FORWARD in sections icmp
sudo sed -i '/-A ufw-before-input -p icmp/s/ACCEPT/DROP/g' /etc/ufw/before.rules
sudo sed -i '/-A ufw-before-forward -p icmp/s/ACCEPT/DROP/g' /etc/ufw/before.rules
# Add new row for source-quench before rule forward
if ! grep -q "source-quench -j DROP" /etc/ufw/before.rules; then
    sudo sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules && echo "Done, row added"
fi
echo "Succes"
# SSH-port configure
echo
echo "=== Configuring SSH Port ==="
# Find row "#Port 22" and change on $SSH_PORT
sudo sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo rm -f /etc/ssh/sshd_config.d/*.conf || true
sudo sshd -t
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket ssh.service || sudo systemctl restart ssh
#
if [ "$CURRENT_PORT" -ne "$SSH_PORT" ]; then
    sudo ufw delete allow $CURRENT_PORT/tcp || true
fi
# ALWAYS open $SSH_PORT and 443
sudo ufw allow $SSH_PORT/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable && sudo ufw status numbered || true

# Auto Security Updates
echo
echo "=== Enabling Auto Security Updates Setup ==="
sudo apt-get install unattended-upgrades -y
sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOT
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOT
echo "Done"

# Cleaning Servise
echo
echo "=== Cleaning Servise ==="
sudo apt-get autoremove -y
sudo apt-get clean
echo "Cleared"
