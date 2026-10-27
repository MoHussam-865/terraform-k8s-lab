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
  type        = string
  default     = "us-east-1"
  # Why us-east-1? Lowest pricing, all instance types available, fewest
  # capacity issues. For production, a variable with no default forces
  # explicit choice per environment.
}

# =============================================================================
# EC2 KEY PAIR — No default, MUST be provided by the user!
# =============================================================================
variable "key_name" {
  description = "Name of an existing AWS EC2 Key Pair for SSH access. MUST exist BEFORE running terraform."
  type        = string

  # No default — forces interactive prompt or tfvars file.
  # Key pairs must pre-exist in AWS; Terraform can't auto-create them.

  validation {
    # Allow only letters, numbers, underscores, and hyphens.
    # `can()` returns true if the expression succeeds, false if it errors.
    # This prevents invalid characters from being passed to AWS API.
    condition     = can(regex("^[a-zA-Z0-9_\\-]+$", var.key_name)) && length(var.key_name) > 0
    error_message = "key_name must only contain letters, numbers, underscores, and hyphens, and cannot be empty."
  }
}

# =============================================================================
# =============================================================================
# UBUNTU AMI FILTER
# =============================================================================
variable "ubuntu_codename" {
  description = "Ubuntu release codename for AMI lookup. jammy=22.04 LTS, noble=24.04 LTS, focal=20.04 LTS"
  type        = string
  default     = "jammy"
  # 22.04 LTS is the most battle-tested release for Kubernetes labs.
  # It has 5 years of support (until 2027) and wide Ansible/K8s tooling support.

  validation {
    condition     = contains(["jammy", "noble", "focal"], var.ubuntu_codename)
    error_message = "ubuntu_codename must be one of: jammy (22.04), noble (24.04), focal (20.04)"
  }
}

# =============================================================================
# VPC CIDR
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the Kubernetes lab VPC"
  type        = string
  default     = "10.1.0.0/24"
  # 10.1.x.x: Leaves 10.0.x.x and 10.2.x.x for future VPCs.
  # /24 = 256 IPs, more than enough. Plan your IP space early
  # to avoid CIDR conflicts when adding VPC peering later.
}

# =============================================================================
# SUBNET CIDR
# =============================================================================
variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.1.0.0/28"
  # /28 = 16 IPs, 11 usable after AWS reserves 5 addresses.
  # AWS reserved: .0(network), .1(router), .2(DNS), .3(future), .15(broadcast)
  # Leaves 11 assignable IPs for our 4 instances + room to grow.
}

# =============================================================================
# PRIVATE IP ADDRESSES — Fixed for Ansible inventory predictability
# =============================================================================
variable "private_ips" {
  description = "Map of hostnames to their fixed private IP addresses within the subnet"
  type        = map(string)
  default = {
    "ansible-controller" = "10.1.0.7"
    "control-plane-01"   = "10.1.0.10"
    "worker-01"          = "10.1.0.6"
    "worker-02"          = "10.1.0.8"
  }
  # Why fixed IPs?
  # Ansible needs a predictable inventory file. If IPs change on every
  # `terraform apply`, your Ansible inventory becomes invalid.
  # These are within the subnet CIDR range (10.1.0.4–10.1.0.14).

  validation {
    condition = alltrue([
      for ip in var.private_ips :
      can(regex("^10\\.1\\.0\\.(6|7|8|10)$", ip))
    ])
    error_message = "All private IPs must be within 10.1.0.6-10.1.0.10 as specified in the architecture."
  }
}

# =============================================================================
# INSTANCE ROOT VOLUME SIZE
# =============================================================================
variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
  # 20 GB is the Ubuntu Server default. K8s images and containers
  # can consume 5-10 GB. 20 GB gives comfortable headroom.
  # AWS Free Tier includes 30 GB of EBS (gp2/gp3) per month.

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 8 and 100 GB."
  }
}
# INSTANCE TYPE
# =============================================================================
variable "instance_type" {
  description = "EC2 instance type for all servers"
  type        = string
  default     = "t3.small"
  # t3.small = 2 vCPU, 2 GB RAM. t3.micro (1 GB) is too small for K8s.
  # At ~$0.0208/hr * 4 instances = ~$0.083/hr → ~$60/month for the full lab.

  validation {
    condition = contains(
      ["t3.small", "t3.medium", "t3a.small", "t3a.medium"], var.instance_type
    )
    error_message = "instance_type must be one of: t3.small, t3.medium, t3a.small, t3a.medium"
  }
}