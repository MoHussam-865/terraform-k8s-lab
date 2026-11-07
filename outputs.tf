# =============================================================================
# FILE:        outputs.tf
# PURPOSE:     Expose useful values after `terraform apply` completes.
#              Outputs are the "return values" of your Terraform project.
# LOADED:      Evaluated after resources are created/updated.
# DEPENDS ON:  ec2.tf, networking.tf, security.tf
#
# WHAT OUTPUTS DO:
#   1. Display values at the end of `terraform apply`
#   2. Queried: `terraform output <name>` or `terraform output -json`
#   3. Used by other Terraform projects via terraform_remote_state
#   4. Consumed by scripts: `terraform output -json | jq ...`
#   5. Self-document what your project produces
# =============================================================================

# =============================================================================
# SSH KEY PAIR OUTPUTS
# =============================================================================

output "key_pair_name" {
  description = "Name of the SSH key pair created by Terraform. Use: ssh -i ~/.ssh/<key_name>.pem ubuntu@<public-ip>"
  value       = aws_key_pair.this.key_name
}

output "key_pair_private_key_path" {
  description = "Local path to the generated private key file for SSH"
  value       = local_file.private_key.filename
}

output "key_pair_fingerprint" {
  description = "Fingerprint of the SSH key pair in AWS"
  value       = aws_key_pair.this.fingerprint
}

# =============================================================================
# VPC & NETWORKING OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC created for the Kubernetes lab"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet where all instances live"
  value       = aws_subnet.public.id
}

output "security_group_ids" {
  description = "Map of per-role security group IDs"
  value = {
    ansible    = aws_security_group.sg_ansible.id
    haproxy    = aws_security_group.sg_haproxy.id
    master     = aws_security_group.sg_master.id
    worker     = aws_security_group.sg_worker.id
    prometheus = aws_security_group.sg_prometheus.id
  }
}

# =============================================================================
# INSTANCE OUTPUTS — Per-Role IPs & IDs
# =============================================================================

# Ansible controller (singleton)
output "ansible_ip" {
  description = "Public IP of the Ansible controller (for SSH access)"
  value       = aws_instance.ansible.public_ip
}

# HAProxy LB instances (for_each with range -> map)
output "haproxy_ips" {
  description = "Map of HAProxy instance keys to their private IPs"
  value = { for key, inst in aws_instance.haproxy : key => inst.private_ip }
}

output "haproxy_public_ips" {
  description = "Map of HAProxy instance keys to their public IPs"
  value = { for key, inst in aws_instance.haproxy : key => inst.public_ip }
}

# Master instances (for_each with range -> map)
output "master_ips" {
  description = "Map of master instance keys to their private IPs"
  value = { for key, inst in aws_instance.master : key => inst.private_ip }
}

output "master_public_ips" {
  description = "Map of master instance keys to their public IPs"
  value = { for key, inst in aws_instance.master : key => inst.public_ip }
}

# Worker instances (for_each with range -> map)
output "worker_ips" {
  description = "Map of worker instance keys to their private IPs"
  value = { for key, inst in aws_instance.worker : key => inst.private_ip }
}

output "worker_public_ips" {
  description = "Map of worker instance keys to their public IPs"
  value = { for key, inst in aws_instance.worker : key => inst.public_ip }
}

# Prometheus server (singleton)
output "prometheus_ip" {
  description = "Public IP of the Prometheus monitoring server"
  value       = aws_instance.prometheus.public_ip
}

# =============================================================================
# EC2 Instance IDs — for AWS CLI operations
# Usage: aws ec2 stop-instances --instance-ids $(terraform output -json instance_ids)
# =============================================================================
output "instance_ids" {
  description = "Map of all instance names to their EC2 instance IDs"
  value = merge(
    { "ansible-controller" = aws_instance.ansible.id },
    { for key, inst in aws_instance.haproxy : "haproxy-${key}" => inst.id },
    { for key, inst in aws_instance.master : "master-${key}" => inst.id },
    { for key, inst in aws_instance.worker : "worker-${key}" => inst.id },
    { "prometheus-server" = aws_instance.prometheus.id }
  )
}

# Public DNS hostnames — alternative to IPs for SSH
output "public_dns" {
  description = "Map of all instance names to their public DNS hostnames"
  value = merge(
    { "ansible-controller" = aws_instance.ansible.public_dns },
    { for key, inst in aws_instance.haproxy : "haproxy-${key}" => inst.public_dns },
    { for key, inst in aws_instance.master : "master-${key}" => inst.public_dns },
    { for key, inst in aws_instance.worker : "worker-${key}" => inst.public_dns },
    { "prometheus-server" = aws_instance.prometheus.public_dns }
  )
}

# =============================================================================
# ANSIBLE INVENTORY — Ready-to-use inventory file
#
# Pipe directly to a file:
#   terraform output -raw ansible_inventory > hosts.ini
# =============================================================================
output "ansible_inventory" {
  description = "Ansible inventory file content in INI format (pipe to file)"

  value = indent(2, <<-EOT
    # Kubernetes Lab Ansible Inventory
    # Generated by Terraform — DO NOT EDIT MANUALLY
    # Run: terraform output -raw ansible_inventory > hosts.ini

    [ansible_controller]
    ${aws_instance.ansible.public_ip} ansible_user=ubuntu private_ip=${aws_instance.ansible.private_ip}

    [haproxy]
    %{ for key, inst in aws_instance.haproxy ~}
    ${inst.private_ip}
    %{ endfor ~}

    [masters]
    %{ for key, inst in aws_instance.master ~}
    ${inst.private_ip}
    %{ endfor ~}

    [workers]
    %{ for key, inst in aws_instance.worker ~}
    ${inst.private_ip}
    %{ endfor ~}

    [prometheus]
    ${aws_instance.prometheus.private_ip}

    [k8s_cluster:children]
    masters
    workers

    [all:vars]
    ansible_python_interpreter=/usr/bin/python3
  EOT
  )
}

# =============================================================================
# Ansible inventory local file path
# =============================================================================
output "ansible_inventory_path" {
  description = "Local path to the generated Ansible inventory file"
  value       = local_file.ansible_hosts.filename
}
