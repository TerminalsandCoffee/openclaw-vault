output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "public_ip" {
  description = "Public IP (for reference only — do NOT SSH here, use Tailscale)"
  value       = aws_instance.openclaw.public_ip
}

output "private_ip" {
  description = "Private IP within VPC"
  value       = aws_instance.openclaw.private_ip
}

output "ami_id" {
  description = "Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.id
}

output "private_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "SSH via Tailscale (after instance joins your tailnet)"
  value       = "ssh -p ${var.ssh_port} ubuntu@${var.hostname}"
}

output "tailscale_ssh_command" {
  description = "SSH via Tailscale SSH (no keys needed)"
  value       = "ssh ${var.hostname}"
}

output "webchat_url" {
  description = "OpenClaw WebChat UI (accessible from your tailnet)"
  value       = "https://${var.hostname}/"
}
