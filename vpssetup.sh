#!/bin/bash

# Close if any error
set -e
# Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or via sudo!"
  exit 1
fi
# Update
echo
echo "=== Updating package lists and upgrading system ==="
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" upgrade -y
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
SKIP_CREATION=false
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
                echo "Deactivating identified swap sources..."
                OTHER_SWAPS=$(swapon --show=NAME,TYPE | grep "file" | awk '{print $1}' | grep -v "/swapfile" || true)
                if [ -f /swapfile ]; then swapoff /swapfile 2>/dev/null || true; fi
                if [ -f /swap.img ]; then swapoff /swap.img 2>/dev/null || true; fi
                for s_file in $OTHER_SWAPS; do
                    if [ -f "$s_file" ]; then
                        echo "Removing old swap file with custom name: $s_file"
                        swapoff "$s_file" 2>/dev/null || true # ИСПРАВЛЕНИЕ: Точечное отключение
                        rm -f "$s_file"
                        sed -i "\|$s_file|d" /etc/fstab
                    fi
                done
                rm -f /swapfile /swap.img
                sed -i '/swap/d' /etc/fstab
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
        fallocate -l "${SWAP_SIZE}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE * 1024))
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        echo "New swapfile successfully created and activated."
    fi
fi
echo
free -h

# DNS Configuration
echo
echo "=== DNS Setup ==="
while true; do
    echo "Select DNS provider:"
    echo "  1) Cloudflare (Speed) [Default]"
    echo "  2) Google (Stability)"
    echo "  3) Quad9 (Privacy)"
    echo "  4) Yandex (For RU segment, Basic filtering)"
    read -p "Your choice (1-4): " DNS_CHOICE
    if [ -z "$DNS_CHOICE" ]; then
        DNS_CHOICE="1"
        echo -e "\e[1A\e[KYour choice (1-4): 1"
    fi
    case "$DNS_CHOICE" in
        1)
            DNS_IPS="1.1.1.1 1.0.0.1"
            DNS_DOT_SERVERS="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com"
            PROVIDER_NAME="Cloudflare"
            TEST_DOMAIN="cloudflare.com"
            break
            ;;
        2)
            DNS_IPS="8.8.8.8 8.8.4.4"
            DNS_DOT_SERVERS="8.8.8.8#dns.google 8.8.4.4#dns.google"
            PROVIDER_NAME="Google"
            TEST_DOMAIN="dns.google"
            break
            ;;
        3)
            DNS_IPS="9.9.9.9 149.112.112.112"
            DNS_DOT_SERVERS="9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net"
            PROVIDER_NAME="Quad9"
            TEST_DOMAIN="dns.quad9.net"
            break
            ;;
        4)
            DNS_IPS="77.88.8.8 77.88.8.1"
            DNS_DOT_SERVERS="77.88.8.8#common.dns.yandex.ru 77.88.8.1#common.dns.yandex.ru"
            PROVIDER_NAME="Yandex"
            TEST_DOMAIN="yandex.ru"
            break
            ;;
        *)
            echo "Error: Invalid choice. Please enter a number between 1 and 4."
            ;;
    esac
done
echo
while true; do
    echo "Do you want to enable DNS over TLS (DoT) for $PROVIDER_NAME? (y/n) [Default: y]"
    read -p "Your choice: " DOT_INPUT
    if [ -z "$DOT_INPUT" ]; then
        DOT_INPUT="y"
        echo -e "\e[1A\e[KYour choice: y"
    fi
    if [ "${DOT_INPUT,,}" = "y" ] || [ "${DOT_INPUT,,}" = "yes" ]; then
        ENABLE_DOT="yes"
        DNS_FINAL_SERVERS="$DNS_DOT_SERVERS"
        DNSSEC_POLICY="no"
        break
    elif [ "${DOT_INPUT,,}" = "n" ] || [ "${DOT_INPUT,,}" = "no" ]; then
        ENABLE_DOT="no"
        DNS_FINAL_SERVERS="$DNS_IPS"
        DNSSEC_POLICY="no"
        break
    else
        echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
    fi
done

echo "Configuring $PROVIDER_NAME (DNS over TLS: $ENABLE_DOT, DNSSEC: $DNSSEC_POLICY)..."

if systemctl list-unit-files | grep -q "systemd-resolved"; then
    rm -f /etc/systemd/resolved.conf.d/dot-custom.conf || true
    mkdir -p /etc/systemd/resolved.conf.d
    
    # Чистая конфигурация БЕЗ разрушительной строки Domains=~.
    tee /etc/systemd/resolved.conf.d/dot-custom.conf > /dev/null <<EOT
[Resolve]
DNS=$DNS_FINAL_SERVERS
DNSOverTLS=$ENABLE_DOT
DNSSEC=$DNSSEC_POLICY
FallbackDNS=8.8.8.8 1.1.1.1
EOT

    systemctl daemon-reload
    systemctl enable systemd-resolved --now >/dev/null 2>&1 || true
    systemctl restart systemd-resolved || true
    
    if [ -f /run/systemd/resolve/stub-resolv.conf ]; then
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi  
    
    # Сброс кэша оперативной памяти
    resolvectl flush-caches >/dev/null 2>&1 || true
    
    echo -e "\n=== Verification ==="
    # Выводим общий статус. Так как кастомных доменных петель больше нет, 
    # здесь отобразится чистая и правильная глобальная конфигурация.
    resolvectl status
    
    echo -e "\n=== DNS Speed & Connectivity Test ==="
    if command -v dig >/dev/null 2>&1; then
        echo "Measuring DNS response time to $TEST_DOMAIN via secure resolver..."
        
        # «Прогреваем» TLS-сессию один раз в фоне, чтобы замер ниже не тормозил
        dig @127.0.0.53 "$TEST_DOMAIN" +short >/dev/null 2>&1 || true
        
        # Настоящий замер скорости
        SPEED_TEST=$(dig @127.0.0.53 "$TEST_DOMAIN" | grep "Query time" || true)
        if [ -n "$SPEED_TEST" ]; then
            echo "Result: $SPEED_TEST"
        else
            echo "DNS Status: Connected, but response time log is unavailable."
        fi
    else
        echo "Utility 'dnsutils' (dig) not found. Performing fallback ping test..."
        if ping -c 2 -W 3 "$TEST_DOMAIN" >/dev/null 2>&1; then
            echo "DNS Status: OK (Domain successfully resolved and pinged)."
        else
            echo "DNS Status: WARNING (Network might be unreachable or domain resolve failed)."
        fi
    fi
else
    echo "Warning: systemd-resolved is not active. Configuring fallback via classic /etc/resolv.conf..."
    if [ "$ENABLE_DOT" = "yes" ]; then
        echo "Notice: DNS over TLS requires systemd-resolved. Setting up standard encrypted fallback instead."
    fi
    sudo rm -f /etc/resolv.conf
    for ip in $DNS_IPS; do
        echo "nameserver $ip" | sudo tee -a /etc/resolv.conf > /dev/null
    done
    echo "Configuration applied via static resolv.conf successfully."
fi

# SSH && UFW
echo
echo "=== IPv6 Configuration in UFW ==="
if [ -f /proc/net/if_inet6 ]; then
    while true; do
        echo "Do you want to DISABLE IPv6 in UFW? (y/n) [Default: n]"
        read -p "Your choice: " IPV6_INPUT
        if [ -z "$IPV6_INPUT" ]; then
            IPV6_INPUT="n"
            echo -e "\e[1A\e[KYour choice: n"
        fi
        if [ "${IPV6_INPUT,,}" = "y" ] || [ "${IPV6_INPUT,,}" = "yes" ]; then
            echo "Disabling IPv6 in UFW configuration..."
            sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
            break
        elif [ "${IPV6_INPUT,,}" = "n" ] || [ "${IPV6_INPUT,,}" = "no" ]; then
            echo "Keeping IPv6 enabled in UFW configuration."
            sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
            break
        else
            echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
        fi
    done
else
    echo "Notice: IPv6 is disabled or not supported by your host provider."
    echo "Disabling IPv6 in UFW automatically to prevent system errors..."
    sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
fi

# UFW No Ping
echo
echo "=== NoPing in UFW Setup ==="
# Точечно отключаем пинг для IPv4
if [ -f /etc/ufw/before.rules ]; then
    sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
    sed -i 's/-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
    
    if ! grep -Fq "source-quench -j DROP" /etc/ufw/before.rules; then
        sed -i '/--icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules
        echo "Done, source-quench row added"
    else
        echo "Source-quench rule already exists, skipping."
    fi
fi

# Точечно отключаем пинг для IPv6 (если он есть в системе), чтобы сервер не пинговался по ipv6-адресу
if [ -f /etc/ufw/before6.rules ]; then
    sed -i 's/-A ufw-before-input -p icmpv6 --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmpv6 --icmp-type echo-request -j DROP/g' /etc/ufw/before6.rules
    sed -i 's/-A ufw-before-forward -p icmpv6 --icmp-type echo-request -j ACCEPT/-A ufw-before-forward -p icmpv6 --icmp-type echo-request -j DROP/g' /etc/ufw/before6.rules
fi
echo "Success"

# SSH-port configure
echo
echo "=== Configuring SSH Port ==="
sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
rm -f /etc/ssh/sshd_config.d/*.conf || true
mkdir -p /run/sshd
sshd -t
systemctl daemon-reload
systemctl restart ssh.socket ssh.service || systemctl restart ssh

echo "Cleaning up old firewall rules..."
sudo ufw delete allow proto tcp from any to any port "$SSH_PORT" comment 'SSH Custom Port' >/dev/null 2>&1 || true
ufw allow "$SSH_PORT"/tcp comment 'SSH Custom Port' >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

echo "Enabling UFW..."
sudo ufw --force enable >/dev/null 2>&1 || true
echo -e "\n=== Final Firewall Status ==="
ufw status verbose | grep -E "Status|To|--" || ufw status

# Auto Security Updates (Оставлен один чистый блок)
echo
echo "=== Enabling Auto Security Updates Setup ==="
echo "Checking for background package managers..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do 
    echo -n "." 
    sleep 3
done
echo " Package manager is free. Proceeding..."
apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install unattended-upgrades -y
tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOT
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOT
echo "Done"

# SSH Tunnel and SFTP User Configuration
echo
echo "=== SSH Tunnel & SFTP User Configuration ==="
    USERNAME="sshtunneluser"
while true; do
    echo "Do you want to create a secure SSH Tunnel + SFTP user ($USERNAME)? (y/n) [Default: n]"
    read -p "Your choice: " TUNNEL_USER_INPUT
    if [ -z "$TUNNEL_USER_INPUT" ]; then
        TUNNEL_USER_INPUT="n"
        echo -e "\e[1A\e[KYour choice: n"
    fi
    if [ "${TUNNEL_USER_INPUT,,}" = "y" ] || [ "${TUNNEL_USER_INPUT,,}" = "yes" ]; then
        CREATE_TUNNEL_USER=true
        echo "Proceeding to configure secure user..."
        break
    elif [ "${TUNNEL_USER_INPUT,,}" = "n" ] || [ "${TUNNEL_USER_INPUT,,}" = "no" ]; then
        CREATE_TUNNEL_USER=false
        echo "Skipping SSH Tunnel + SFTP user setup."
        break
    else
        echo -e "Error: Invalid input. Please enter 'y' or 'n'\n"
    fi
done
if [ "$CREATE_TUNNEL_USER" = true ]; then
    if id "$USERNAME" &>/dev/null; then
      echo "User '$USERNAME' already exists. Skipping creation."
    else
      echo "Creating user '$USERNAME' (Passwordless & Silent)..."
      useradd -m -s /bin/bash -p '!' "$USERNAME"
      echo "User successfully created."
    fi
    echo "Configuring Chroot permissions for home directory..."
    chown root:root "/home/$USERNAME"
    chmod 755 "/home/$USERNAME"
    SSH_DIR="/home/$USERNAME/.ssh"
    if [ ! -d "$SSH_DIR" ]; then
      echo "Creating directory $SSH_DIR..."
      mkdir -p "$SSH_DIR"
    fi
    if [ -f "$SSH_DIR/authorized_keys" ] || (compgen -G "$SSH_DIR/*.pub" >/dev/null 2>&1 || false); then
      echo "authorized_keys or a public key (*.pub) already exists. Skipping key generation."
    else
      echo "No keys or authorized_keys found. Generating new Ed25519 key..."
      rm -f "$SSH_DIR/id_ed25519" 2>/dev/null || true
      ssh-keygen -t ed25519 -a 100 -N "" -C "sshtunneluser@identificator" -f "$SSH_DIR/id_ed25519"
      cat "$SSH_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"
      echo "SSH key successfully generated and added to authorized_keys."
    fi
    chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    if [ -f "$SSH_DIR/authorized_keys" ]; then chmod 600 "$SSH_DIR/authorized_keys"; fi
    find "$SSH_DIR" -type f ! -name "*.pub" ! -name "authorized_keys" -exec chmod 600 {} + 2>/dev/null || true
    find "$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
    SFTP_DIR="/home/$USERNAME/Download"
    if [ ! -d "$SFTP_DIR" ]; then
      echo "Creating 'Download' directory for SFTP..."
      mkdir -p "$SFTP_DIR"
    fi
    chown "$USERNAME:$USERNAME" "$SFTP_DIR"
    chmod 755 "$SFTP_DIR"
    SSHD_CONFIG="/etc/ssh/sshd_config"
    sed -i '/# === BEGIN SSHTUNNELUSER BLOCK ===/,/# === END SSHTUNNELUSER BLOCK ===/d' "$SSHD_CONFIG"
    echo "Adding security restrictions (Tunnel + SFTP) to $SSHD_CONFIG..."
    tee -a "$SSHD_CONFIG" > /dev/null << 'EOF'
# === BEGIN SSHTUNNELUSER BLOCK ===
Match User sshtunneluser
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTTY no
    PasswordAuthentication no
    ChrootDirectory /home/sshtunneluser
    ForceCommand internal-sftp
# === END SSHTUNNELUSER BLOCK ===
EOF
    echo "Checking SSH configuration for syntax errors..."
    mkdir -p /run/sshd
    if ! sshd -t; then
      echo "Error: Syntax errors found in $SSHD_CONFIG! Reverting changes..."
      sed -i '/# === BEGIN SSHTUNNELUSER BLOCK ===/,/# === END SSHTUNNELUSER BLOCK ===/d' "$SSHD_CONFIG"
      exit 1
    fi
    echo "Restarting SSH service..."
    if systemctl is-active --quiet sshd; then
      systemctl restart sshd
    elif systemctl is-active --quiet ssh; then
      systemctl restart ssh
    else
      echo "Warning: Could not determine SSH service name."
    fi
    echo
    echo "=== Configuration successfully completed! ==="
    echo "User '$USERNAME' can now use BOTH SSH Tunneling and SFTP."
    echo "Terminal login is securely BLOCKED."
    echo "------------------------------------------------------------"
    PRIVATE_KEY_FILE=$(find "$SSH_DIR" -type f ! -name "*.pub" ! -name "authorized_keys" | head -n 1)
    if [ -n "$PRIVATE_KEY_FILE" ] && [ -f "$PRIVATE_KEY_FILE" ]; then
        KEY_NAME=$(basename "$PRIVATE_KEY_FILE")
        trap 'rm -f "$PRIVATE_KEY_FILE"; echo -e "\n\n✅ [TRAP] Private key file ($KEY_NAME) permanently deleted due to script interruption."; exit' INT TERM EXIT
        echo "🔑 YOUR PRIVATE SSH KEY ($KEY_NAME):"
        echo "------------------------------------------------------------"
        cat "$PRIVATE_KEY_FILE"
        echo "------------------------------------------------------------"
        echo "⚠️ CRITICAL SECURITY WARNING:"
        echo "Copy the key text above right now into your client device."
        echo "Once you press Enter (or press Ctrl+C), this private key will be PERMANENTLY deleted."
        echo "------------------------------------------------------------"
        read -p "Press [Enter] after you have copied the key to delete it safely..."
        rm -f "$PRIVATE_KEY_FILE"
        echo "✅ Private key file '$KEY_NAME' has been safely deleted from the VPS."
        trap - INT TERM EXIT
    else
        echo "ℹ️ Note: No new private key file found on the server (already deleted or skipped)."
    fi
    echo "------------------------------------------------------------"
fi

# Cleaning Service
echo
echo "=== Cleaning Service & Deep Disk Cleanup ==="
if [ -f /swap.img ]; then 
    echo "Found old /swap.img. Deactivating and removing..." 
    swapoff /swap.img 2>/dev/null || true 
    rm -f /swap.img 
    sed -i '\/swap.img/d' /etc/fstab
fi

if command -v journalctl >/dev/null 2>&1; then 
    echo "Vacuuming systemd journal logs to 100M..." 
    journalctl --vacuum-size=100M >/dev/null 2>&1 || true
fi

echo "Clearing heavy system logs..."
truncate -s 0 /var/log/syslog 2>/dev/null || true
rm -f /var/log/syslog.1 2>/dev/null || true
rm -f /var/log/syslog.*.gz 2>/dev/null || true

echo "Configuring custom logrotate policy for syslog..."
tee /etc/logrotate.d/syslog-custom > /dev/null << 'EOF'
/var/log/syslog { 
    daily 
    rotate 2 
    maxsize 50M 
    missingok 
    notifempty 
    delaycompress 
    compress 
    postrotate 
        /usr/lib/rsyslog/rsyslog-rotate 
    endscript
}
EOF

if command -v docker >/dev/null 2>&1; then 
    echo "Cleaning unused Docker resources..." 
    docker system prune -f >/dev/null 2>&1 || true
fi

echo "Running APT package cleanup..."
apt-get autoclean -y
apt-get autoremove --purge -y
apt-get clean -y
echo "Cleared"
echo
df -h /
