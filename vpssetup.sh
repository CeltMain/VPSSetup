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
        echo "Your SSH-port: $CURRENT_PORT. Do you want to change it? (y/n) [Default: n]"
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

# Swap file Setup
echo
echo "=== Swap file Setup ==="
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
echo "Detected RAM: ${TOTAL_RAM}MB"
while true; do
    echo "Do you want to create a swap file? (y/n) [Default: y]"
    read -p "Your choice: " SWAP_INPUT
    if [ -z "$SWAP_INPUT" ]; then
        SWAP_INPUT="y"
        echo -e "\e[1A\e[KYour choice: y"
    fi
    if [ "${SWAP_INPUT,,}" = "y" ] || [ "${SWAP_INPUT,,}" = "yes" ]; then
        CREATE_SWAP=true
        break
    elif [ "${SWAP_INPUT,,}" = "n" ] || [ "${SWAP_INPUT,,}" = "no" ]; then
        CREATE_SWAP=false
        echo "Skipping swap file creation by user request."
        break
    else
        echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
    fi
done
if [ "$CREATE_SWAP" = true ]; then
    CURRENT_ACTIVE_SWAP=$(free -m | awk '/^Swap:/{print $2}')
    if [ "$CURRENT_ACTIVE_SWAP" -gt 0 ]; then
        EXISTING_SWAP_SIZE=$(free -h | awk '/^Swap:/{print $2}')
        while true; do
            echo "Active Swap detected. Total current size is: $EXISTING_SWAP_SIZE"
            echo "Do you want to REMOVE ALL existing swap sources and create ONE clean swap file? (y/n) [Default: n]"
            read -p "Your choice: " REPLACE_INPUT
            if [ -z "$REPLACE_INPUT" ]; then 
                REPLACE_INPUT="n"
                echo -e "\e[1A\e[KYour choice: n"
            fi
            if [ "${REPLACE_INPUT,,}" = "y" ] || [ "${REPLACE_INPUT,,}" = "yes" ]; then
                echo "Deactivating ALL current swap sources..."
                OTHER_SWAPS=$(swapon --show=NAME,TYPE | grep "file" | awk '{print $1}' | grep -v "/swapfile" || true)
                sudo swapoff -a || true
                for s_file in $OTHER_SWAPS; do
                    if [ -f "$s_file" ]; then
                        echo "Removing old swap file with custom name: $s_file"
                        sudo rm -f "$s_file"
                        sudo sed -i "\|$s_file|d" /etc/fstab
                    fi
                done
                sudo rm -f /swapfile /swap.img
                sudo sed -i '/swap/d' /etc/fstab
                break
            elif [ "${REPLACE_INPUT,,}" = "n" ] || [ "${REPLACE_INPUT,,}" = "no" ]; then
                SKIP_CREATION=true
                echo "Keeping existing swap configuration."
                break
            else
                echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
            fi
        done
    fi
    if [ "$SKIP_CREATION" != true ]; then
        while true; do
            echo "Enter swap file size in Gigabytes (e.g., 1, 2, 4)"
            read -p "Size (Default: 2): " SWAP_SIZE
            if [ -z "$SWAP_SIZE" ]; then
                SWAP_SIZE=2
                echo -e "\e[1A\e[KSize (Default: 2): 2"
                break
            fi
            if [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "$SWAP_SIZE" -gt 0 ]; then
                echo "Selected swap size: ${SWAP_SIZE}GB"
                break
            else
                echo -e "Error: Invalid format. Please enter a positive integer (e.g. 1, 2, 4).\n"
            fi
        done
        echo "Creating a new ${SWAP_SIZE}GB swap file..."
        sudo fallocate -l "${SWAP_SIZE}G" /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE * 1024))
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        echo "New swapfile successfully created and activated."
    fi
fi
echo
free -h

# DNS over TLS (Safe and Lightweight)
echo
echo "=== DNS over TLS (DoT) Setup ==="
while true; do
    echo "Do you want to enable DNS over TLS (DoT)? (y/n) [Default: y]"
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
        echo "  1) Cloudflare [Default]"
        echo "  2) Quad9"
        echo "  3) Google"
        echo "  4) Yandex (Good for RU segment)"
        read -p "Your choice (1-4) [Default: 1]: " DNS_CHOICE
        if [ -z "$DNS_CHOICE" ]; then
            DNS_CHOICE="1"
            echo -e "\e[1A\e[KYour choice (1-4): 1"
        fi
        
        case "$DNS_CHOICE" in
            1)
                DNS_SERVERS="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com"
                PROVIDER_NAME="Cloudflare"
                break
                ;;
            2)
                DNS_SERVERS="9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net"
                PROVIDER_NAME="Quad9"
                break
                ;;
            3)
                DNS_SERVERS="8.8.8.8#dns.google 8.8.4.4#dns.google"
                PROVIDER_NAME="Google"
                break
                ;;
            4)
                DNS_SERVERS="77.88.8.8#common.dot.dns.yandex.net 77.88.8.1#common.dot.dns.yandex.net"
                PROVIDER_NAME="Yandex"
                break
                ;;
            *)
                echo "Error: Invalid choice. Please enter a number between 1 and 4."
                ;;
        esac
    done

    echo "Configuring $PROVIDER_NAME DNS over TLS (DNSSEC: no)..."
    
    # 1. Безопасно бэкапим текущий resolv.conf на случай полного отката
    if [ ! -f /etc/resolv.conf.bak ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    fi

    # 2. Создаем чистую конфигурацию (DNSSEC полностью отключен)
    sudo rm -f /etc/systemd/resolved.conf.d/*.conf || true
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/dot-custom.conf > /dev/null <<EOT
[Resolve]
DNS=$DNS_SERVERS
Domains=~.
DNSOverTLS=yes
DNSSEC=no
EOT

    # Применяем настройки
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    sudo systemctl daemon-reload
    sudo systemctl restart systemd-resolved

    # Сбрасываем динамические DNS от DHCP на основном интерфейсе, чтобы они не мешали DoT
    NET_INT=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -n "$NET_INT" ]; then
        sudo resolvectl dns "$NET_INT" "" 2>/dev/null || true
        sudo resolvectl domain "$NET_INT" "" 2>/dev/null || true
    fi

    # === БЛОК ПРОВЕРКИ И ЗАЩИТЫ ОТ БЛОКИРОВОК/ПЕРЕХВАТА ===
    echo "Verifying DoT connection integrity..."
    sleep 2 # Даем пару секунд на установку TLS-сессии

    # Пробуем разрешить тестовый домен строго через настроенные параметры
    if resolvectl query google.com >/dev/null 2>&1; then
        echo "Success! DNS over TLS is fully operational."
    else
        echo "ALERT: DoT handshake failed or connection is intercepted/blocked!"
        echo "Rolling back to default hoster DNS immediately for safety..."
        
        # Откат: удаляем кастомный конфиг
        sudo rm -f /etc/systemd/resolved.conf.d/dot-custom.conf
        
        # Возвращаем стандартный resolv.conf провайдера (если был бэкап) или перезапускаем сеть
        if [ -f /etc/resolv.conf.bak ]; then
            sudo cp /etc/resolv.conf.bak /etc/resolv.conf
        else
            sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        fi
        
        sudo systemctl daemon-reload
        sudo systemctl restart systemd-resolved
        echo "Rollback complete. System is safe."
    fi
fi

echo -e "\n=== Current DNS Status ==="
resolvectl status

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
sudo mkdir -p /run/sshd
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
sudo apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install unattended-upgrades -y
sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOT
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOT
echo "Done"

# Cleaning Servise
echo
echo "=== Cleaning Service & Deep Disk Cleanup ==="
if [ -f /swap.img ]; then
    echo "Found old /swap.img. Deactivating and removing..."
    sudo swapoff /swap.img 2>/dev/null || true
    sudo rm -f /swap.img
    sudo sed -i '\/swap.img/d' /etc/fstab
fi
if command -v journalctl >/dev/null 2>&1; then
    echo "Vacuuming systemd journal logs to 100M..."
    sudo journalctl --vacuum-size=100M >/dev/null 2>&1 || true
fi
echo "Clearing heavy system logs..."
sudo truncate -s 0 /var/log/syslog 2>/dev/null || true
sudo rm -f /var/log/syslog.1 2>/dev/null || true
sudo rm -f /var/log/syslog.*.gz 2>/dev/null || true
if [ -f /etc/logrotate.d/rsyslog ]; then
    echo "Optimizing logrotate configuration for syslog..."
    sudo sed -i 's/weekly/daily\n        maxsize 50M/' /etc/logrotate.d/rsyslog
    sudo sed -i 's/rotate 4/rotate 2/' /etc/logrotate.d/rsyslog
    sudo sed -i 's/rotate 7/rotate 2/' /etc/logrotate.d/rsyslog
fi
if command -v docker >/dev/null 2>&1; then
    echo "Cleaning unused Docker resources..."
    sudo docker system prune -f >/dev/null 2>&1 || true
fi
echo "Running APT package cleanup..."
sudo apt-get autoclean -y
sudo apt-get autoremove --purge -y
sudo apt-get clean -y
echo "Cleared"
echo
df -h /
