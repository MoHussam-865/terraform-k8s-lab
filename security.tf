# =============================================================================
# FILE:        security.tf
# PURPOSE:     Define Security Groups — the virtual firewall around EC2 instances.
#              SGs operate at the INSTANCE level (attached to ENIs, not subnets).
# LOADED:      At plan time. SGs are just configuration until attached to an EC2.
# OPTIONAL:    No. EC2 API requires at least one SG per instance launch.
# DEPENDS ON:  networking.tf (references aws_vpc.main.id)
# =============================================================================

# =============================================================================
# SECURITY GROUP — Kubernetes Lab
#
# KEY CONCEPTS ABOUT SECURITY GROUPS:
#
# 1. STATEFUL: If you allow inbound on port 22, the response traffic is
#    AUTOMATICALLY allowed outbound. You don't need a matching egress rule.
#    NACLs (Network ACLs) are STATELESS and need explicit rules both ways.
#
# 2. DEFAULT-DENY: An empty SG blocks ALL traffic. You must explicitly ALLOW
#    everything needed. This is "least privilege" security by default.
#
# 3. ATTACHED TO ENI: SGs attach to Elastic Network Interfaces (ENIs), not
#    subnets. Each EC2 instance has ≥1 ENI. SGs from all attached ENIs are
#    merged (union of all rules).
#
# 4. ALLOW-ONLY: SGs have no DENY rules. If not explicitly allowed, denied.
#    This makes security reasoning much simpler.
#
# 5. SG SELF-REFERENCING: SGs can reference other SGs as sources. Example:
#    "Allow traffic FROM web-server-SG TO database-SG on port 3306."
#    The SG ID auto-resolves to all instances in that group.
# =============================================================================
resource "aws_security_group" "k8s_lab" {

  # Unique name within the VPC
  name = "${local.name_prefix}-sg"

  # Human-readable description — be specific so nobody deletes it accidentally
  description = "Security group for K8s lab: SSH (22) and K8s API (6443)"

  # SG is VPC-scoped — only applies to instances inside our lab VPC
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg"
  }
}

# =============================================================================
# INGRESS RULES — Traffic ENTERING instances
#
# We use aws_security_group_rule (separate resources) instead of inline
# `ingress {}` blocks. This is a PRODUCTION BEST PRACTICE because:
#   - Rules are independently manageable
#   - Adding/removing rules doesn't touch the parent SG
#   - Self-referencing rules (SG→SG) are cleaner
#   - Avoids "inline rules will be removed" pitfall during refactoring
# =============================================================================

# -----------------------------------------------------------------------------
# INGRESS: SSH (port 22) — Secure Shell for remote administration
#
# Protocol: TCP; Port: 22; Source: 0.0.0.0/0 (any IPv4)
#
# ⚠️  0.0.0.0/0 means SSH from THE ENTIRE INTERNET.
# ACCEPTABLE for a short-lived lab. PRODUCTION alternatives (ordered best→worst):
#   1. AWS SSM Session Manager — NO open ports (IAM-based auth, modern)
#   2. VPN + private subnet — SSH only from VPN CIDR
#   3. Bastion host — jump box, other instances accept SSH only from bastion SG
#   4. Your office IP — cidr_blocks = ["203.0.113.5/32"]
#   5. Temporary — use your current public IP (check whatismyip.com)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_lab.id
  description       = "Allow SSH from anywhere (LAB ONLY — restrict in production!)"
}

# -----------------------------------------------------------------------------
# INGRESS: Kubernetes API Server (port 6443)
#
# kube-apiserver binds to 0.0.0.0:6443 on the control plane node.
# This is where kubectl connects, worker nodes register, and kubelet
# communicates with the control plane. kubeadm defaults to 6443.
#
# Needed for:
#   - Worker nodes registering with control plane
#   - Ansible controller running kubectl/kubeadm commands
#   - Your local machine for kubectl (optional for lab)
#
# ⚠️  Production: restrict to known client CIDRs (VPN/office IP).
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ingress_k8s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_lab.id
  description       = "Allow Kubernetes API server access (6443)"
}

# =============================================================================
# EGRESS RULES — Traffic LEAVING instances
# =============================================================================

# -----------------------------------------------------------------------------
# EGRESS: Allow ALL outbound traffic
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # "-1" = all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_lab.id
  description       = "Allow all outbound traffic (for package downloads, Docker pulls, etc.)"
}

# =============================================================================
# SECURITY GROUP DESIGN COMPLETE!
# =============================================================================