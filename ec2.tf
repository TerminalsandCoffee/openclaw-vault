# --- Key Pair ---
resource "tls_private_key" "openclaw" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "openclaw" {
  key_name   = "openclaw-key"
  public_key = tls_private_key.openclaw.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.openclaw.private_key_openssh
  filename        = "${path.module}/openclaw-key.pem"
  file_permission = "0600"
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

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.openclaw.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "openclaw" {
  name = "openclaw-ec2-profile"
  role = aws_iam_role.openclaw.name
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
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = var.hostname
    ssh_port           = var.ssh_port
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  tags = { Name = "openclaw" }
}
