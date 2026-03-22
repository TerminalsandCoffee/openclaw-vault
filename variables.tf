variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g., us-east-1, eu-west-2)."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "Must be a valid EC2 instance type (e.g., t3.micro, t3.medium)."
  }
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

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 10.0.1.0/24)."
  }
}

variable "hostname" {
  description = "Hostname for the instance on your tailnet"
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.hostname))
    error_message = "Hostname must be lowercase alphanumeric with hyphens, 1-63 chars."
  }
}

variable "ssh_port" {
  description = "SSH port (non-default to reduce noise)"
  type        = number
  default     = 2222

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1024 and 65535 (unprivileged range)."
  }
}

variable "openclaw_api_key" {
  description = "Anthropic API key for the OpenClaw agent model"
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.openclaw_api_key, "sk-ant-")
    error_message = "Anthropic API key must start with 'sk-ant-'."
  }
}

variable "openclaw_model" {
  description = "Model ID for the OpenClaw agent"
  type        = string
  default     = "anthropic/claude-sonnet-4-5-20250929"
}
