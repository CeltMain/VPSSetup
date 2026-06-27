#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- SETTINGS ---
USERNAME="sshtunneluser"
# ------------------

echo "=== Starting SSH Tunnel + SFTP User Configuration ==="

# 1. Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or via sudo!"
  exit 1
fi

# 2. Create user if it doesn't exist
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists. Skipping creation."
else
  echo "Creating user '$USERNAME' with blocked shell..."
  useradd -m -s /bin/false "$USERNAME"
fi

# 3. CRITICAL FOR CHROOT: Home directory must be owned by root
echo "Configuring Chroot permissions for home directory..."
chown root:root "/home/$USERNAME"
chmod 755 "/home/$USERNAME"

# 4. Setup .ssh directory
SSH_DIR="/home/$USERNAME/.ssh"

if [ -d "$SSH_DIR" ]; then
  echo "Directory $SSH_DIR already exists. Updating ownership..."
else
  echo "Creating directory $SSH_DIR..."
  mkdir -p "$SSH_DIR"
fi

# [FIXED FOR CHROOT] SSH folder inside chroot MUST be owned by root
chown -R root:root "$SSH_DIR"
chmod 755 "$SSH_DIR"

# Keys inside chroot must be readable by root, but strict enough for SSH
if [ -f "$SSH_DIR/authorized_keys" ]; then
  chmod 644 "$SSH_DIR/authorized_keys"
fi
if [ -f "$SSH_DIR/id_ed25519.pub" ]; then
  chmod 644 "$SSH_DIR/id_ed25519.pub"
fi

# 5. Create a dedicated writable directory named 'Download' for SFTP
SFTP_DIR="/home/$USERNAME/Download"
if [ ! -d "$SFTP_DIR" ]; then
  echo "Creating writable 'Download' directory for SFTP..."
  mkdir -p "$SFTP_DIR"
fi
chown "$USERNAME:$USERNAME" "$SFTP_DIR"
chmod 755 "$SFTP_DIR"

# 6. Configure /etc/ssh/sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"

# Clean up any old configurations for this user to avoid conflicts
sed -i '/# Security settings for SSH tunnel user/,/ForceCommand/d' "$SSHD_CONFIG"
sed -i '/Match User sshtunneluser/,/ForceCommand/d' "$SSHD_CONFIG"
sed -i '/# Security settings for SSH tunnel and SFTP user/,/ForceCommand/d' "$SSHD_CONFIG"

echo "Adding security restrictions (Tunnel + SFTP) to $SSHD_CONFIG..."
cat << 'EOF' >> "$SSHD_CONFIG"

# Security settings for SSH tunnel and SFTP user
Match User sshtunneluser
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTTY no
    ChrootDirectory /home/sshtunneluser
    ForceCommand internal-sftp
EOF

# 7. Validate configuration before restart
echo "Checking SSH configuration for syntax errors..."
if ! sshd -t; then
  echo "Error: Syntax errors found in $SSHD_CONFIG! Please fix them manually."
  exit 1
fi

# 8. Restart SSH service
echo "Restarting SSH service..."
if systemctl is-active --quiet sshd; then
  systemctl restart sshd
elif systemctl is-active --quiet ssh; then
  systemctl restart ssh
else
  echo "Warning: Could not determine SSH service name. Please restart it manually."
fi

echo "=== Configuration successfully completed! ==="
echo "User can now use both SSH Tunneling and SFTP."
echo "NOTE: For file transfers via SFTP, use the 'Download' directory."
