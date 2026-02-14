# OpenClaw Vault

Terraform template that provisions a **hardened Ubuntu 24.04 LTS EC2 instance** on AWS with:

- **Security hardening** — SSH lockdown, UFW firewall, kernel sysctl hardening, auditd, fail2ban, auto security updates
- **Tailscale VPN** — Zero-config mesh networking with Tailscale SSH (no public SSH exposure)
- **Zero public attack surface** — No inbound security group rules; all access via Tailscale only
- **IMDSv2 enforced** — Instance metadata service v2 required (prevents SSRF token theft)
- **SSM access** — AWS Systems Manager for emergency out-of-band management

## Architecture

<img width="1337" height="721" alt="image" src="https://github.com/user-attachments/assets/c929240e-0274-4059-813b-4458d31cfcb7" />

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.12
- AWS CLI configured (`aws configure`)
- [Tailscale account](https://tailscale.com/) with an auth key

### Generate a Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Generate an **auth key** (reusable or one-time)
3. Copy the key — it starts with `tskey-auth-`

## Quick Start

<img width="1339" height="720" alt="image" src="https://github.com/user-attachments/assets/8e02fab5-480f-41b3-8132-8cb92e8e6777" />


```bash
# Clone
git clone https://github.com/yourusername/openclaw-vault.git
cd openclaw-vault

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Tailscale auth key

# Deploy
terraform init
terraform plan
terraform apply
```

After apply completes, wait 2-3 minutes for cloud-init to finish, then:

```bash
# Option 1: Tailscale SSH (no keys needed — recommended)
ssh openclaw

# Option 2: Traditional SSH via Tailscale IP
ssh -i openclaw-key.pem -p 2222 ubuntu@openclaw
```

## What Gets Hardened

| Layer | What | Details |
|-------|------|---------|
| **Network** | Security group | Zero inbound rules — no public SSH, HTTP, or anything |
| **Network** | UFW firewall | Deny all incoming, allow outgoing, SSH only on tailscale0 |
| **Access** | Tailscale | Mesh VPN with Tailscale SSH — access via your tailnet only |
| **Access** | SSH | Root login disabled, password auth disabled, port moved to 2222 |
| **Access** | IMDSv2 | Instance metadata requires token (prevents SSRF attacks) |
| **Access** | Fail2ban | 3 failed attempts = 1 hour ban |
| **Kernel** | sysctl | IP spoofing protection, SYN flood mitigation, ICMP hardening, ASLR |
| **Monitoring** | auditd | Watches auth, identity files, sudoers, SSH config, cron, network config |
| **Updates** | unattended-upgrades | Automatic daily security patches |
| **Misc** | Cleanup | Telnet removed, file permissions tightened, core dumps disabled |

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `tailscale_auth_key` | Tailscale auth key (sensitive) | — |
| `hostname` | Instance hostname on tailnet | `openclaw` |
| `ssh_port` | SSH port (non-default) | `2222` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `subnet_cidr` | Subnet CIDR block | `10.0.1.0/24` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | EC2 instance ID |
| `public_ip` | Public IP (reference only — don't SSH here) |
| `private_ip` | VPC private IP |
| `ssh_command` | Traditional SSH command via Tailscale |
| `tailscale_ssh_command` | Tailscale SSH command (keyless) |
| `private_key_path` | Path to generated .pem file |

## Verify Hardening

<img width="1235" height="584" alt="image" src="https://github.com/user-attachments/assets/9d547e0a-0485-47cd-9082-d9a65533ab4e" />


After SSH-ing in via Tailscale:

```bash
# Check setup log
cat /var/log/openclaw-setup.log

# Verify Tailscale
tailscale status

# Verify firewall
sudo ufw status verbose

# Verify fail2ban
sudo fail2ban-client status sshd

# Verify auditd
sudo auditctl -l

# Verify sysctl
sudo sysctl net.ipv4.conf.all.rp_filter
sudo sysctl net.ipv4.tcp_syncookies

# Verify auto-updates
systemctl status unattended-upgrades
```

## Teardown

```bash
terraform destroy
```

## License

MIT
