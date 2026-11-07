# =============================================================================
# FILE:        variables.tf
# PURPOSE:     Define all input variables — the "API contract" of this project.
# LOADED:      At plan/apply time, before any resources are evaluated.
# OPTIONAL:    Technically yes, but without variables your project is
#              inflexible and every change requires editing .tf files.
# DEPENDS ON:  Nothing. Variables are the entry point.
#
# HOW VARIABLES ARE SET (priority order, highest to lowest):
#   1. Command line:     terraform apply -var="key_name=my-key"
#   2. *.auto.tfvars:    Files matching *.auto.tfvars (loaded automatically)
#   3. terraform.tfvars: The default variable definitions file
#   4. Environment vars: TF_VAR_key_name="my-key"
#   5. Default value:    The `default` argument in this file (LOWEST priority)
#
# If NO value is provided and NO default exists, Terraform PROMPTS
# interactively at plan/apply time. This is great for development
# but blocks automation. Production projects should always have
# either defaults or a variables file.
# =============================================================================

# =============================================================================
# AWS REGION
# =============================================================================
variable "aws_region" {
  description = "AWS region where all infrastructure will be provisioned"
  type = string
  default = "us-east-1"
  # Why us-east-1? Lowest pricing, all instance types available, fewest
  # capacity issues. For production, a variable with no default forces
  # explicit choice per environment.
}

# =============================================================================
# EC2 KEY PAIR — Terraform creates it; you just choose the name.
# =============================================================================
variable "key_name" {
  description = "Name for the SSH key pair that Terraform will create in AWS. The private key is saved to ~/.ssh/<key_name>.pem"
  type = string
  default = "k8s-lab-key"

  # Default provided — no interactive prompt needed.
  # Terraform auto-generates an RSA-4096 key and creates the
  # aws_key_pair resource from the public key. The private key
  # is saved locally to ~/.ssh/<key_name>.pem.

  validation {
    # Allow only letters, numbers, underscores, and hyphens.
    # `can()` returns true if the expression succeeds, false if it errors.
    # This prevents invalid characters from being passed to AWS API.
    condition = can(regex("^[a-zA-Z0-9_\\-]+$", var.key_name)) && length(var.key_name) > 0
    error_message = "key_name must only contain letters, numbers, underscores, and hyphens, and cannot be empty."
  }
}

# =============================================================================
# =============================================================================
# UBUNTU AMI FILTER
# =============================================================================
variable "ubuntu_codename" {
  description = "Ubuntu release codename for AMI lookup. jammy=22.04 LTS, noble=24.04 LTS, focal=20.04 LTS"
  type = string
  default = "jammy"
  # 22.04 LTS is the most battle-tested release for Kubernetes labs.
  # It has 5 years of support (until 2027) and wide Ansible/K8s tooling support.

  validation {
    condition = contains(["jammy", "noble", "focal"], var.ubuntu_codename)
    error_message = "ubuntu_codename must be one of: jammy (22.04), noble (24.04), focal (20.04)"
  }
}

# =============================================================================
# VPC CIDR
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the Kubernetes lab VPC"
  type = string
  default = "10.1.0.0/24"
  # 10.1.x.x: Leaves 10.0.x.x and 10.2.x.x for future VPCs.
  # /24 = 256 IPs, more than enough. Plan your IP space early
  # to avoid CIDR conflicts when adding VPC peering later.
}

# =============================================================================
# SUBNET CIDR
# =============================================================================
variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type = string
  default = "10.1.0.0/26"
  # /26 = 64 IPs, 59 usable after AWS reserves 5 addresses.
  # AWS reserved: .0(network), .1(router), .2(DNS), .3(future), .63(broadcast)
  # Leaves 59 assignable IPs for up to ~50 instances with room to grow.
  # Expanded from /28 to /26 to accommodate 8+ instances + scalability.
}

# =============================================================================
# MASTER COUNT — Number of K8s control plane nodes (must be odd for etcd)
# =============================================================================
variable "master_count" {
  description = "Number of Kubernetes control plane (master) nodes. Must be odd for etcd quorum."
  type = number
  default = 3

  validation {
    condition = var.master_count >= 1 && var.master_count % 2 == 1
    error_message = "master_count must be an odd number (1, 3, 5, 7, ...) for etcd quorum and at least 1."
  }
}

# =============================================================================
# WORKER COUNT — Number of K8s worker nodes
# =============================================================================
variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type = number
  default = 2

  validation {
    condition = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

# =============================================================================
# HAPROXY COUNT — Number of HAProxy load balancer instances
# =============================================================================
variable "haproxy_count" {
  description = "Number of HAProxy load balancer instances"
  type = number
  default = 1

  validation {
    condition = var.haproxy_count >= 1
    error_message = "haproxy_count must be at least 1."
  }
}

# =============================================================================
# INSTANCE ROOT VOLUME SIZE
# =============================================================================
variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type = number
  default = 20
  # 20 GB is the Ubuntu Server default. K8s images and containers
  # can consume 5-10 GB. 20 GB gives comfortable headroom.
  # AWS Free Tier includes 30 GB of EBS (gp2/gp3) per month.

  validation {
    condition = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 8 and 100 GB."
  }
}
# INSTANCE TYPE
# =============================================================================
variable "instance_type" {
  description = "EC2 instance type for all servers"
  type = string
  default = "t3.small"
  # t3.small = 2 vCPU, 2 GB RAM. t3.micro (1 GB) is too small for K8s.
  # At ~$0.0208/hr * 4 instances = ~$0.083/hr → ~$60/month for the full lab.

  validation {
    condition = contains(
      ["t3.small", "t3.medium", "t3a.small", "t3a.medium"], var.instance_type
    )
    error_message = "instance_type must be one of: t3.small, t3.medium, t3a.small, t3a.medium"
  }
}