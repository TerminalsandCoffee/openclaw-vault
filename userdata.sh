#!/bin/bash
set -euo pipefail

# Log everything for debugging
exec > >(tee /var/log/openclaw-setup.log) 2>&1
echo "=== OpenClaw Hardened Instance Setup: $(date) ==="

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# 1. SYSTEM UPDATE + AWS CLI
# ============================================================
echo "[1/13] Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install AWS CLI for Secrets Manager retrieval
echo "[2/13] Installing AWS CLI..."
apt-get install -y awscli

# ============================================================
# 2. RETRIEVE SECRETS FROM AWS SECRETS MANAGER
# ============================================================
echo "[3/13] Retrieving secrets from Secrets Manager..."
TAILSCALE_AUTH_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${tailscale_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

OPENCLAW_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${openclaw_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

# ============================================================
# 3. INSTALL TAILSCALE
# ============================================================
echo "[4/13] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Join tailnet with SSH enabled (allows keyless SSH via Tailscale identity)
tailscale up \
  --authkey="$TAILSCALE_AUTH_KEY" \
  --ssh \
  --hostname="${hostname}"

# Clear secret from memory
unset TAILSCALE_AUTH_KEY

echo "Tailscale IP: $(tailscale ip -4)"

# ============================================================
# 3. SSH HARDENING
# ============================================================
echo "[5/13] Hardening SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/openclaw.conf << 'SSHEOF'
# OpenClaw SSH Hardening
Port ${ssh_port}
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowTcpForwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
SSHEOF

systemctl restart sshd

# ============================================================
# 4. UFW FIREWALL
# ============================================================
echo "[6/13] Configuring firewall..."
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing

# Allow SSH only on Tailscale interface
ufw allow in on tailscale0 to any port ${ssh_port} proto tcp comment "SSH via Tailscale"

# Allow OpenClaw Gateway on Tailscale interface
ufw allow in on tailscale0 to any port 18789 proto tcp comment "OpenClaw Gateway via Tailscale"

ufw --force enable

# ============================================================
# 5. KERNEL HARDENING (SYSCTL)
# ============================================================
echo "[7/13] Applying kernel hardening..."
cat > /etc/sysctl.d/99-openclaw.conf << 'SYSCTL'
# --- IP Spoofing Protection ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# --- Disable Source Routing ---
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# --- Ignore ICMP Redirects ---
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# --- Don't Send Redirects ---
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# --- SYN Flood Protection ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# --- Ignore ICMP Broadcasts ---
net.ipv4.icmp_echo_ignore_broadcasts = 1

# --- Log Suspicious Packets ---
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# --- Disable IPv6 (not needed) ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# --- Restrict Core Dumps ---
fs.suid_dumpable = 0

# --- ASLR ---
kernel.randomize_va_space = 2
SYSCTL

sysctl -p /etc/sysctl.d/99-openclaw.conf

# ============================================================
# 6. AUTOMATIC SECURITY UPDATES
# ============================================================
echo "[8/13] Configuring automatic security updates..."
apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'AUTOUPDATE'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
AUTOUPDATE

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOCONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOCONF

systemctl enable unattended-upgrades

# ============================================================
# 7. AUDITD
# ============================================================
echo "[9/13] Installing and configuring auditd..."
apt-get install -y auditd audisp-plugins

cat > /etc/audit/rules.d/openclaw.rules << 'AUDITRULES'
# Delete any existing rules
-D

# Set buffer size
-b 8192

# Auth and identity
-w /var/log/auth.log -p wa -k auth_log
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Privilege escalation
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH config
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# Cron
-w /etc/crontab -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# Network config
-w /etc/hosts -p wa -k network
-w /etc/network/ -p wa -k network
-w /etc/netplan/ -p wa -k network

# Firewall
-w /etc/ufw/ -p wa -k firewall

# Make audit config immutable (requires reboot to change)
-e 2
AUDITRULES

systemctl enable auditd
systemctl restart auditd

# ============================================================
# 8. FAIL2BAN
# ============================================================
echo "[10/13] Installing and configuring fail2ban..."
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << FAIL2BAN
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ${ssh_port}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
FAIL2BAN

systemctl enable fail2ban
systemctl restart fail2ban

# ============================================================
# 9. CLEANUP & FINAL HARDENING
# ============================================================
echo "[11/13] Final hardening..."

# Remove unnecessary packages
apt-get purge -y telnet 2>/dev/null || true
apt-get autoremove -y

# File permissions
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config.d/openclaw.conf
chmod 644 /etc/passwd
chmod 600 /etc/shadow
chmod 644 /etc/group
chmod 600 /etc/gshadow

# Login banner
cat > /etc/motd << 'MOTD'

  ___                    ____ _
 / _ \ _ __   ___ _ __  / ___| | __ ___      __
| | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /
| |_| | |_) |  __/ | | | |___| | (_| |\ V  V /
 \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/
      |_|

  Hardened Instance | Unauthorized access is prohibited
  All activity is monitored and logged via auditd

MOTD

# Set hostname
hostnamectl set-hostname "${hostname}"

# ============================================================
# 10. INSTALL NODE.JS 22
# ============================================================
echo "[12/13] Installing Node.js 22..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# ============================================================
# 11. INSTALL & CONFIGURE OPENCLAW
# ============================================================
echo "[13/13] Installing and configuring OpenClaw..."
npm install -g openclaw@latest

# Create openclaw config directory
sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw

# Write OpenClaw config — gateway bound to loopback, served via Tailscale
# API key retrieved from Secrets Manager earlier, not baked into user_data
sudo -u ubuntu tee /home/ubuntu/.openclaw/openclaw.json > /dev/null << EOF
{
  "agent": {
    "model": "${openclaw_model}"
  },
  "models": {
    "providers": {
      "anthropic": {
        "apiKey": "$OPENCLAW_API_KEY"
      }
    }
  },
  "gateway": {
    "port": 18789,
    "bind": "loopback",
    "tailscale": { "mode": "serve" },
    "auth": {
      "allowTailscale": true
    }
  }
}
EOF

# Restrict config file permissions (contains API key)
chmod 600 /home/ubuntu/.openclaw/openclaw.json

# Clear secret from memory
unset OPENCLAW_API_KEY

# ============================================================
# START OPENCLAW GATEWAY (SYSTEMD USER SERVICE)
# ============================================================
echo "Starting OpenClaw Gateway..."

# Enable linger so user services start without login (critical for headless)
loginctl enable-linger ubuntu

# Install the daemon as ubuntu user
sudo -u ubuntu openclaw onboard --install-daemon --headless

# Start the gateway service
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/$(id -u ubuntu) systemctl --user start openclaw-gateway

echo "=== OpenClaw Setup Complete: $(date) ==="
echo "=== Tailscale IP: $(tailscale ip -4) ==="
echo "=== SSH Port: ${ssh_port} ==="
