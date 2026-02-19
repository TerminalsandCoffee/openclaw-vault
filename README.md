# OpenClaw Vault

Terraform template that provisions a **hardened Ubuntu 24.04 LTS EC2 instance** on AWS with:

- **Security hardening** — SSH lockdown, UFW firewall, kernel sysctl hardening, auditd, fail2ban, auto security updates
- **Tailscale VPN** — Zero-config mesh networking with Tailscale SSH (no public SSH exposure)
- **OpenClaw AI Agent** — OpenClaw Gateway + WebChat GUI, served privately via Tailscale Serve
- **Zero public attack surface** — No inbound security group rules; all access via Tailscale only
- **IMDSv2 enforced** — Instance metadata service v2 required (prevents SSRF token theft)
- **SSM access** — AWS Systems Manager for emergency out-of-band management

## Architecture

<img width="1337" height="721" alt="image" src="https://github.com/user-attachments/assets/c929240e-0274-4059-813b-4458d31cfcb7" />

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.12
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured
- [Tailscale account](https://tailscale.com/) with an auth key
- [Anthropic API key](https://console.anthropic.com/) for the OpenClaw agent model

### Configure AWS CLI

Terraform uses your AWS credentials to create resources. If you skip this step, you'll get an error like `no EC2 IMDS role found`.

1. [Install the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) if you haven't already
2. Create an access key in the [IAM Security Credentials console](https://console.aws.amazon.com/iam/home#/security_credentials)
3. Run `aws configure` and enter your credentials:

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1
# Default output format: json
```

4. Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN. If this command fails, Terraform will too.

### Generate a Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Generate an **auth key** (reusable or one-time)
3. Copy the key — it starts with `tskey-auth-`

### Get an Anthropic API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Create an API key
3. Copy the key — it starts with `sk-ant-`

## Quick Start

<img width="1339" height="720" alt="image" src="https://github.com/user-attachments/assets/8e02fab5-480f-41b3-8132-8cb92e8e6777" />

```bash
# Clone
git clone https://github.com/TerminalsandCoffee/openclaw-vault
cd openclaw-vault

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Tailscale auth key and Anthropic API key

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

### Access WebChat

Once the instance is ready, open the WebChat GUI from any device on your tailnet:

```
https://openclaw/
```

Tailscale Serve handles HTTPS automatically — no certificates to configure.

## What Gets Hardened

| Layer | What | Details |
|-------|------|---------|
| **Network** | Security group | Zero inbound rules — no public SSH, HTTP, or anything |
| **Network** | UFW firewall | Deny all incoming, allow outgoing, SSH + Gateway only on tailscale0 |
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
| `instance_type` | EC2 instance type | `t3.medium` |
| `tailscale_auth_key` | Tailscale auth key (sensitive) | — |
| `hostname` | Instance hostname on tailnet | `openclaw` |
| `ssh_port` | SSH port (non-default) | `2222` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `subnet_cidr` | Subnet CIDR block | `10.0.1.0/24` |
| `openclaw_api_key` | Anthropic API key (sensitive) | — |
| `openclaw_model` | Model ID for the agent | `anthropic/claude-sonnet-4-5-20250929` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | EC2 instance ID |
| `public_ip` | Public IP (reference only — don't SSH here) |
| `private_ip` | VPC private IP |
| `ssh_command` | Traditional SSH command via Tailscale |
| `tailscale_ssh_command` | Tailscale SSH command (keyless) |
| `private_key_path` | Path to generated .pem file |
| `webchat_url` | OpenClaw WebChat URL (tailnet only) |

## Verify Setup

<img width="1235" height="584" alt="image" src="https://github.com/user-attachments/assets/9d547e0a-0485-47cd-9082-d9a65533ab4e" />

After SSH-ing in via Tailscale:

```bash
# Check setup log (should show all 12 steps completed)
cat /var/log/openclaw-setup.log

# Verify Tailscale
tailscale status

# Verify Node.js
node --version   # should be v22+

# Verify OpenClaw
openclaw doctor
openclaw status

# Verify Gateway service
systemctl --user status openclaw-gateway

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

## Troubleshooting

### `no EC2 IMDS role found` / `failed to refresh cached credentials`

Your AWS CLI isn't configured. Run `aws configure` with your access key and secret key. See [Configure AWS CLI](#configure-aws-cli) above.

### `terraform init` fails with `wsarecv: An existing connection was forcibly closed`

This is an IPv6 connectivity issue with the Terraform registry (common on some ISPs). Fix by adding a temporary hosts file entry to force IPv4:

```bash
# Get the IPv4 address
nslookup registry.terraform.io

# Add to your hosts file (requires admin/sudo)
# Windows: C:\Windows\System32\drivers\etc\hosts
# Linux/macOS: /etc/hosts
13.224.187.70 registry.terraform.io
```

Run `terraform init` again, then remove the hosts entry after it succeeds.

### `VpcLimitExceeded`

AWS allows 5 VPCs per region by default. Either delete an unused VPC in the [VPC console](https://console.aws.amazon.com/vpc/home), switch to a different region in `terraform.tfvars`, or [request a limit increase](https://console.aws.amazon.com/servicequotas/).

### Instance deploys but can't SSH via Tailscale

Wait 3-5 minutes after `terraform apply` for cloud-init to complete. Check if the `openclaw` node appears in your [Tailscale admin console](https://login.tailscale.com/admin/machines). If it doesn't, the Tailscale auth key may be expired or invalid — generate a new one and redeploy.

### OpenClaw Gateway not running after deploy

The systemd user service can have timing issues during cloud-init. SSH in and start it manually:

```bash
ssh openclaw
systemctl --user start openclaw-gateway
systemctl --user status openclaw-gateway
```

## Teardown

```bash
terraform destroy
```

## License

MIT
