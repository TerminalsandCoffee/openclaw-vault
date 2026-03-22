# --- Key Pair ---
resource "tls_private_key" "openclaw" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "openclaw" {
  key_name   = "openclaw-key"
  public_key = tls_private_key.openclaw.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content              = tls_private_key.openclaw.private_key_openssh
  filename             = "${path.module}/openclaw-key.pem"
  file_permission      = "0400"
  directory_permission = "0700"
}

# --- Security Group ---
# No inbound from public internet. All access via Tailscale.
resource "aws_security_group" "openclaw" {
  name        = "openclaw-sg"
  description = "OpenClaw - egress only, no public inbound"
  vpc_id      = aws_vpc.openclaw.id

  # Tailscale needs outbound to coordinate + system updates
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (Tailscale + updates)"
  }

  tags = { Name = "openclaw-sg" }
}

# --- IAM Role (SSM access for emergency out-of-band management) ---
resource "aws_iam_role" "openclaw" {
  name = "openclaw-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = { Name = "openclaw-ec2-role" }
}

# Minimal SSM policy — only what's needed for Session Manager access
resource "aws_iam_role_policy" "ssm_minimal" {
  name = "openclaw-ssm-minimal"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMCore"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

# Read-only access to Secrets Manager for runtime secret retrieval
resource "aws_iam_role_policy" "secrets_read" {
  name = "openclaw-secrets-read"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.tailscale_key.arn,
          aws_secretsmanager_secret.openclaw_api_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "openclaw" {
  name = "openclaw-ec2-profile"
  role = aws_iam_role.openclaw.name
}

# --- Secrets Manager ---
# Secrets stored here instead of user_data (which is visible in AWS Console + state)
resource "aws_secretsmanager_secret" "tailscale_key" {
  name                    = "openclaw/tailscale-auth-key"
  description             = "Tailscale auth key for OpenClaw instance enrollment"
  recovery_window_in_days = 0 # Allow immediate deletion on destroy
}

resource "aws_secretsmanager_secret_version" "tailscale_key" {
  secret_id     = aws_secretsmanager_secret.tailscale_key.id
  secret_string = var.tailscale_auth_key
}

resource "aws_secretsmanager_secret" "openclaw_api_key" {
  name                    = "openclaw/anthropic-api-key"
  description             = "Anthropic API key for OpenClaw agent"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "openclaw_api_key" {
  secret_id     = aws_secretsmanager_secret.openclaw_api_key.id
  secret_string = var.openclaw_api_key
}

# --- EC2 Instance ---
resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.openclaw.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.openclaw.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name

  user_data = templatefile("${path.module}/userdata.sh", {
    tailscale_secret_arn = aws_secretsmanager_secret.tailscale_key.arn
    openclaw_secret_arn  = aws_secretsmanager_secret.openclaw_api_key.arn
    aws_region           = var.aws_region
    hostname             = var.hostname
    ssh_port             = var.ssh_port
    openclaw_model       = var.openclaw_model
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1 # Prevent container/SSRF metadata escape
  }

  tags = { Name = "openclaw" }
}
