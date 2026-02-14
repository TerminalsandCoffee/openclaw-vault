variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for automatic enrollment"
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.tailscale_auth_key, "tskey-auth-")
    error_message = "Tailscale auth key must start with 'tskey-auth-'."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "hostname" {
  description = "Hostname for the instance"
  type        = string
  default     = "openclaw"
}

variable "ssh_port" {
  description = "SSH port (moved from default 22)"
  type        = number
  default     = 2222
}
