# =============================================================================
# FILE:        ec2.tf
# PURPOSE:     Provision all EC2 instances for the Kubernetes lab.
#              Uses per-role for_each with range() for scalable instance counts.
# LOADED:      At plan time. Dependency graph ensures VPC â†’ Subnet â†’ SG â†’ EC2.
# OPTIONAL:    No - this is the whole point of the project!
# DEPENDS ON:  networking.tf, security.tf, variables.tf, locals.tf
#
# INSTANCES CREATED (at default counts):
#   1. aws_instance.ansible     â†’ 1 singleton  (sg_ansible)
#   2. aws_instance.haproxy     â†’ N=1 map      (sg_haproxy)
#   3. aws_instance.master      â†’ N=3 map      (sg_master)
#   4. aws_instance.worker      â†’ N=2 map      (sg_worker)
#   5. aws_instance.prometheus  â†’ 1 singleton  (sg_prometheus)
#
# KEY DESIGN DECISION: for_each with range() NOT count
#
#   âŒ count = N approach:
#     resource "aws_instance" "this" { count = 3 }
#     Instances: this[0], this[1], this[2]
#     Changing from 3 to 5 shifts indices â†’ destroys & recreates ALL
#
#   âœ… for_each with toset(range(N)) approach (OUR CHOICE):
#     resource "aws_instance" "this" { for_each = toset(range(3)) }
#     Instances: this["0"], this["1"], this["2"]
#     Changing from 3 to 5 creates this["3"], this["4"] WITHOUT touching 0-2
#
#   This is the #1 most impactful Terraform design decision for scalability.
#   for_each over range() gives stable keys ["0","1","2"] so scaling up
#   only adds new instances - existing ones are NEVER disrupted.
#
#   Singletons (ansible, prometheus) use no for_each - just one instance.
# =============================================================================
# =============================================================================
# DATA SOURCE: Find the latest Ubuntu 22.04 LTS AMI
#
# Instead of hardcoding an AMI ID like "ami-0c7217cdde317cfec", we use
# a data source to dynamically find the LATEST Ubuntu AMI for our chosen
# release. Hardcoded AMIs are fragile - they get deprecated or updated,
# and AMI IDs differ PER REGION. ami-xxx in us-east-1 is DIFFERENT from
# ami-xxx in eu-west-1.
#
# This data source queries AWS at plan time and returns the most recent
# AMI matching our filters. Every `terraform plan` checks for a newer
# AMI. If one exists, Terraform shows it as a change (forces instance
# recreation unless you prevent it with lifecycle rules).
# =============================================================================
data "aws_ami" "ubuntu" {
  # most_recent = true: If multiple AMIs match, return the newest one.
  # This ensures we always get the latest security patches.
  most_recent = true
  # ---------------------------------------------------------------------------
  # owners: Who published the AMI.
  # "099720109477" is Canonical's OFFICIAL AWS account ID.
  # Using this (instead of "amazon" or "self") ensures we get the
  # OFFICIAL Ubuntu image, not a potentially compromised community AMI.
  #
  # IMPORTANT: This account ID is DOCUMENTED by Canonical at:
  # https://ubuntu.com/server/docs/cloud-platforms
  # Always verify owner IDs from official sources, never from forum posts.
  # ---------------------------------------------------------------------------
  owners = ["099720109477"]
  # ---------------------------------------------------------------------------
  # filter blocks - server-side filtering on the AWS API.
  # These filters are sent to AWS, which returns only matching AMIs.
  # This is MUCH faster than fetching all AMIs and filtering locally.
  #
  # Each filter has:
  #   - name:   The AWS AMI attribute to filter on
  #   - values: A list of acceptable values
  #
  # Multiple filters are ANDed together (all must match).
  # Multiple values within one filter are ORed (any matches).
  # ---------------------------------------------------------------------------
  # Filter 1: AMI name pattern
  # Matches official Ubuntu images like:
  #   ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20240126
  filter {
    name = "name"
    # Format: ubuntu/images/hvm-ssd/ubuntu-<codename>-<version>-amd64-server-*
    # hvm = Hardware Virtual Machine (modern virtualization, required for t3)
    # ssd = EBS-backed with SSD optimization
    # amd64 = x86_64 architecture (not ARM)
    # server = Server edition (not minimal or desktop)
    # * = any date suffix (we want the latest via most_recent = true)
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-22.04-amd64-server-*"]
  }
  # Filter 2: Virtualization type
  # hvm = Hardware Virtual Machine. This is the standard virtualization
  # type for all modern instance types (t2+, m5+, c5+, etc.). The older
  # "paravirtual" (PV) type is deprecated and not supported by t3.
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  # Filter 3: Root device type
  # ebs = Elastic Block Store. The root volume is an EBS volume (persistent
  # storage separate from the physical host). This allows stopping/starting
  # instances without losing data and supports snapshots.
  # "instance-store" = ephemeral (data lost on stop) - not suitable here.
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
  # Filter 4: Architecture
  # x86_64 = standard Intel/AMD 64-bit. Our t3.small uses x86_64.
  # arm64 would be for t4g / Graviton instances (different AMI needed).
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
}
# =============================================================================
# SSH KEY PAIR GENERATION - Fully automated, no user prompt needed.
#
# These resources generate an RSA-4096 key pair locally, upload the
# public key to AWS as an EC2 Key Pair, and save the private key to
# ~/.ssh/<key_name>.pem for SSH access.
#
# Before this change, the project required a PRE-EXISTING key pair in
# AWS and prompted for the key_name interactively (no default value).
# Now Terraform handles the entire lifecycle:
#   1. tls_private_key.this   - generates RSA-4096 key locally
#   2. aws_key_pair.this      - imports public key into AWS
#   3. local_file.private_key - saves private key to disk (0600 perms)
#
# SECURITY NOTE: The private key WILL be stored in Terraform state
# (as a side effect of tls_private_key). For a learning lab this is
# acceptable. In production, generate keys outside Terraform and use
# the aws_key_pair resource to import only the public key.
# =============================================================================
# -----------------------------------------------------------------------------
# RESOURCE: tls_private_key - Generate an RSA-4096 key pair locally.
# Terraform runs this on your machine - the private key never touches
# AWS during generation. Only the public key is uploaded.
# -----------------------------------------------------------------------------
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits = 4096
}
# -----------------------------------------------------------------------------
# RESOURCE: aws_key_pair - Upload the public key to AWS so EC2 can
# inject it into ~/.ssh/authorized_keys on instance launch.
#
# AWS only stores the PUBLIC key (fingerprint). The private key stays
# in Terraform state and in the local file we create below.
# -----------------------------------------------------------------------------
resource "aws_key_pair" "this" {
  key_name = var.key_name
  public_key = tls_private_key.this.public_key_openssh
  tags = {
    Name = var.key_name
  }
}
# -----------------------------------------------------------------------------
# RESOURCE: local_file - Save the private key to disk so you can SSH.
#
# File is saved to ~/.ssh/<key_name>.pem with 0600 permissions
# (owner-only read/write - SSH refuses keys with wider permissions).
#
# If you change key_name on a subsequent apply, a NEW file is written
# (and a NEW key pair is created in AWS, since key_name changes force
# replacement of aws_key_pair).
# -----------------------------------------------------------------------------
resource "local_file" "private_key" {
  content = tls_private_key.this.private_key_pem
  filename = pathexpand("~/.ssh/${var.key_name}.pem")
  file_permission = "0600"
}
# =============================================================================
# EC2 INSTANCES - Per-role, scalable, dynamic private IPs
#
# Masters and Workers are created FIRST (independently, in parallel).
# HAProxy and Prometheus follow (depend on targets for their config).
# Ansible Controller is LAST - runs the playbook against all ready nodes.
#
# Each non-ansible instance gets:
#   1. ansible-managed.sh bootstrap (creates ansadmin, SSH config)
#   2. id_rsa.pub public SSH key for ansadmin access
#
# The Ansible controller gets:
#   1. ansadmin user + SSH directory
#   2. id_rsa + id_rsa.pub (private key for SSH to managed nodes)
#   3. Dynamically generated /etc/ansible/hosts with ALL IPs
#   4. ansible-controller.sh (sets up ansible.cfg, runs playbook)
# =============================================================================
# =============================================================================
# 1. AWS INSTANCE: master - Kubernetes Control Plane Nodes
#
# Master nodes run the K8s control plane (etcd, kube-apiserver, etc.).
# Created in parallel with workers - no inter-dependency.
# Scaled via var.master_count (default 3, must be odd for etcd quorum).
# =============================================================================
resource "aws_instance" "master" {
  depends_on = [aws_security_group_rule.master_egress_all]
  # ---------------------------------------------------------------------------
  # for_each - iterate using range() for stable "0","1","2" keys
  # toset(range(N)) produces {"0", "1", ..., "N-1"} - adding N doesn't
  # shift existing keys, so scaling up only creates NEW instances.
  # ---------------------------------------------------------------------------
  for_each = toset([for i in range(var.master_count) : tostring(i)])
  # ---------------------------------------------------------------------------
  # ami - Amazon Machine Image (OS template).
  # ---------------------------------------------------------------------------
  ami = data.aws_ami.ubuntu.id
  # ---------------------------------------------------------------------------
  # instance_type - t3.small = 2 vCPU, 2 GB RAM
  # ---------------------------------------------------------------------------
  instance_type = var.instance_type
  # ---------------------------------------------------------------------------
  # subnet_id - All instances in the same public subnet
  # ---------------------------------------------------------------------------
  subnet_id = aws_subnet.public.id
  # ---------------------------------------------------------------------------
  # vpc_security_group_ids - Per-role SG for control plane nodes
  # sg_master allows: SSH from ansible, 6443 from haproxy+self, etcd,
  # kubelet, controller-manager, scheduler, node-exporter (9100).
  # ---------------------------------------------------------------------------
  vpc_security_group_ids = [aws_security_group.sg_master.id]
  # ---------------------------------------------------------------------------
  # associate_public_ip_address - Public IPv4 for SSH access
  # ---------------------------------------------------------------------------
  associate_public_ip_address = true
  # ---------------------------------------------------------------------------
  # NO private_ip - AWS auto-assigns from subnet (dynamic IPs, Goal #1)
  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # key_name - EC2 Key Pair (auto-generated, saved to ~/.ssh/<name>.pem)
  # ---------------------------------------------------------------------------
  key_name = aws_key_pair.this.key_name
  # ---------------------------------------------------------------------------
  # root_block_device - The root EBS volume configuration.
  #
  # Every EC2 instance has at least one EBS volume: the root device.
  # Without this block, AWS uses the AMI's default size (usually 8 GB
  # for Ubuntu Server). We increase it to 20 GB for Docker images.
  #
  # EBS (Elastic Block Store) = network-attached persistent storage.
  # It survives instance stop/start (unlike instance store, which is
  # ephemeral physical disk directly attached to the host).
  # ---------------------------------------------------------------------------
  root_block_device {
    # -------------------------------------------------------------------------
    # volume_size - Size in GiB (Gibibytes, not Gigabytes. 1 GiB = 1.074 GB).
    # 20 GiB is comfortable for: Ubuntu Server (~3 GB) + Docker images
    # (~5-10 GB) + logs + temp files.
    # AWS Free Tier: 30 GB of EBS (gp2/gp3) per month.
    # -------------------------------------------------------------------------
    volume_size = var.root_volume_size
    # -------------------------------------------------------------------------
    # volume_type - The EBS volume type.
    #
    # gp3 (General Purpose SSD v3):
    #   - 3000 IOPS baseline (included), 125 MB/s throughput (included)
    #   - Can independently provision up to 16000 IOPS and 1000 MB/s
    #   - 20% cheaper than gp2 for the same performance
    #   - Recommended by AWS for most workloads
    #
    # gp2 (General Purpose SSD v2):
    #   - 3 IOPS per GiB baseline (20 GB = 60 IOPS - very low!)
    #   - Burst capability up to 3000 IOPS
    #   - Still widely used but gp3 is strictly better for new projects
    #
    # io1/io2 (Provisioned IOPS): For high-performance databases. $$$.
    # st1/sc1 (Throughput Optimized/Cold HDD): For big data. Not for boot.
    # -------------------------------------------------------------------------
    volume_type = "gp3"
    # -------------------------------------------------------------------------
    # delete_on_termination - What happens to the EBS volume when the
    # instance is terminated (destroyed)?
    #
    # true = Volume is deleted (our choice: no orphaned volumes, clean)
    # false = Volume persists (useful if you want to recover data after
    #         accidental termination, but you pay for orphaned volumes)
    #
    # For a lab, true is correct. Terraform destroys everything cleanly.
    # For databases in production, false + snapshots is common.
    # -------------------------------------------------------------------------
    delete_on_termination = true
    # -------------------------------------------------------------------------
    # encrypted - Encrypt the EBS volume at rest using AWS KMS.
    #
    # true = Data is encrypted on the physical disk (our choice)
    # false = Data is stored unencrypted
    #
    # AWS KMS encryption is FREE for EBS (uses the AWS-managed key).
    # There is ZERO reason not to encrypt root volumes in 2024.
    # Encryption is transparent to the OS and applications.
    #
    # Encrypted volumes also mean snapshots are encrypted, and any
    # volumes created FROM those snapshots are encrypted too.
    # -------------------------------------------------------------------------
    encrypted = true
    # -------------------------------------------------------------------------
    # tags - EBS-specific tags. These are SEPARATE from the instance tags.
    # Useful for cost allocation: you can filter AWS Cost Explorer by
    # volume tags to see how much you spend on storage vs compute.
    # -------------------------------------------------------------------------
    tags = {
      Name = "${local.name_prefix}-master-${format("%02d", each.key + 1)}-root-vol"
    }
  }
  # ---------------------------------------------------------------------------
  # tags - EC2 instance metadata.
  #
  # "Name" tag: Appears as the Name column in the AWS EC2 Console.
  # Without it, you see anonymous instance IDs. ALWAYS set a Name tag.
  #
  # The "Role" tag helps with:
  #   - AWS Cost Explorer filtering (cost per role)
  #   - AWS Resource Groups (group by role)
  #   - Ansible dynamic inventory (filter by tag)
  #   - Scripting and automation (describe-instances --filter)
  #
  # Provider-level default_tags (from provider.tf) are MERGED with
  # these instance-level tags. If there's a key collision, the
  # instance-level tag wins.
  # ---------------------------------------------------------------------------
  tags = {
    Name = "${local.name_prefix}-master-${format("%02d", each.key + 1)}"
    Role = "control-plane"
  }
  # ===========================================================================
  # CONNECTION - SSH configuration for Terraform provisioners
  #
  # Connect as ubuntu (default AMI user) using the auto-generated key pair.
  # The ansadmin user doesn't exist yet - it's created by the bootstrap script.
  # ===========================================================================
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = tls_private_key.this.private_key_pem
    timeout = "10m"
  }
  # ===========================================================================
  # PROVISIONER 1: Upload ansible-managed.sh bootstrap script
  # ===========================================================================
  provisioner "file" {
    source = "${path.module}/scripts/ansible-managed.sh"
    destination = "/home/ubuntu/ansible-managed.sh"
  }
  provisioner "file" {
    source = "${path.module}/keys/id_rsa.pub"
    destination = "/home/ubuntu/id_rsa.pub"
  }
  # ===========================================================================
  # PROVISIONER 2: Run the bootstrap script + add SSH public key
  #
  # Runs ansible-managed.sh (creates ansadmin user, installs dependencies,
  # configures SSH), then appends the public key from ./keys/id_rsa.pub
  # to ansadmin's authorized_keys so the ansible controller can connect.
  # ===========================================================================
  provisioner "remote-exec" {
    inline = [
      "sudo bash /home/ubuntu/ansible-managed.sh",
      "sudo tee -a /home/ansadmin/.ssh/authorized_keys < /home/ubuntu/id_rsa.pub",
      "sudo rm '/home/ubuntu/id_rsa.pub'",
      "sudo chown ansadmin:ansadmin /home/ansadmin/.ssh/authorized_keys",
      "sudo chmod 600 /home/ansadmin/.ssh/authorized_keys",
    ]
  }
  # ===========================================================================
  # LIFECYCLE - Controls how Terraform manages this resource's lifecycle
  #
  # The lifecycle block customizes Terraform's standard create/update/destroy
  # behavior. This is an ADVANCED feature used sparingly, but it's critical
  # for certain scenarios.
  #
  # Common lifecycle rules:
  #   create_before_destroy (bool)   - Create replacement first, then destroy old
  #   prevent_destroy       (bool)   - Error instead of destroying (safety lock)
  #   ignore_changes        (list)   - Ignore specific attribute changes
  #   replace_triggered_by  (list)   - Force recreate when referenced value changes
  # ===========================================================================
  lifecycle {
    # -------------------------------------------------------------------------
    # ignore_changes - Tells Terraform: "If these attributes change outside
    # of Terraform, DON'T try to fix them on the next apply."
    #
    # We ignore changes to the AMI because:
    #   1. Our data source finds the LATEST Ubuntu AMI every `plan`
    #   2. If Canonical publishes a new AMI, Terraform would want to
    #      DESTROY and RECREATE all instances to use the new AMI
    #   3. For a learning lab, destroying instances because a new AMI
    #      exists is disruptive and unnecessary
    #
    # Without this, every time Ubuntu releases a patch, `terraform plan`
    # shows "ami changed â†’ forces replacement" for all 4 instances.
    # That destroys your K8s cluster. NOT what you want during a lab.
    #
    # Production consideration:
    #   - Some teams WANT AMI auto-rotation (immutable infrastructure)
    #   - They use launch templates + Auto Scaling Groups, not individual
    #     EC2 instances, so replacement is automatic and safe
    #   - For single-instance workloads (like this lab), ignore_changes
    #     prevents unwanted destruction
    #
    # We also ignore changes to the root_block_device's volume_type
    # because changing volume type after creation requires stopping the
    # instance first. Terraform can't do that automatically.
    # -------------------------------------------------------------------------
    ignore_changes = [
      ami,                              # Don't replace on new AMI release
      root_block_device[0].volume_type  # Don't modify volume type after creation
    ]
    # -------------------------------------------------------------------------
    # prevent_destroy - If true, Terraform REFUSES to destroy this resource.
    # terraform destroy will ERROR instead of terminating the instance.
    #
    # We set it to FALSE (explicitly) because this is a lab - we WANT to
    # be able to destroy everything. In production, you might set this to
    # true for databases and stateful workloads that should never be
    # accidentally deleted.
    #
    # Example: prevent_destroy = true on an RDS database means you must
    # explicitly remove the lifecycle rule before you can destroy it.
    # This prevents "terraform destroy" from nuking production data.
    # -------------------------------------------------------------------------
    prevent_destroy = false
  }
}
# =============================================================================
# 2. WORKER - Kubernetes Worker Nodes
# =============================================================================
resource "aws_instance" "worker" {
  depends_on = [aws_security_group_rule.worker_egress_all]
  for_each = toset([for i in range(var.worker_count) : tostring(i)])
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg_worker.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.this.key_name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    delete_on_termination = true
    encrypted = true
    tags = {
      Name = "${local.name_prefix}-worker-${format("%02d", each.key + 1)}-root-vol"
    }
  }
  tags = {
    Name = "${local.name_prefix}-worker-${format("%02d", each.key + 1)}"
    Role = "worker"
  }
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = tls_private_key.this.private_key_pem
    timeout = "10m"
  }
  provisioner "file" {
    source = "${path.module}/scripts/ansible-managed.sh"
    destination = "/home/ubuntu/ansible-managed.sh"
  }
  provisioner "file" {
    source = "${path.module}/keys/id_rsa.pub"
    destination = "/home/ubuntu/id_rsa.pub"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo bash /home/ubuntu/ansible-managed.sh",
      "sudo tee -a /home/ansadmin/.ssh/authorized_keys < /home/ubuntu/id_rsa.pub",
      "sudo rm '/home/ubuntu/id_rsa.pub'",
      "sudo chown ansadmin:ansadmin /home/ansadmin/.ssh/authorized_keys",
      "sudo chmod 600 /home/ansadmin/.ssh/authorized_keys",
    ]
  }
  lifecycle {
    ignore_changes = [ami, root_block_device[0].volume_type]
    prevent_destroy = false
  }
}
# =============================================================================
# 3. HAPROXY - HAProxy Load Balancer
# =============================================================================
resource "aws_instance" "haproxy" {
  for_each = toset([for i in range(var.haproxy_count) : tostring(i)])
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg_haproxy.id]
  associate_public_ip_address = true
  depends_on = [aws_security_group_rule.haproxy_egress_all]
  key_name = aws_key_pair.this.key_name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    delete_on_termination = true
    encrypted = true
    tags = {
      Name = "${local.name_prefix}-haproxy-${format("%02d", each.key + 1)}-root-vol"
    }
  }
  tags = {
    Name = "${local.name_prefix}-haproxy-${format("%02d", each.key + 1)}"
    Role = "haproxy"
  }
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = tls_private_key.this.private_key_pem
    timeout = "10m"
  }
  provisioner "file" {
    source = "${path.module}/scripts/ansible-managed.sh"
    destination = "/home/ubuntu/ansible-managed.sh"
  }
  provisioner "file" {
    source = "${path.module}/keys/id_rsa.pub"
    destination = "/home/ubuntu/id_rsa.pub"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo bash /home/ubuntu/ansible-managed.sh",
      "sudo tee -a /home/ansadmin/.ssh/authorized_keys < /home/ubuntu/id_rsa.pub",
      "sudo rm '/home/ubuntu/id_rsa.pub'",
      "sudo chown ansadmin:ansadmin /home/ansadmin/.ssh/authorized_keys",
      "sudo chmod 600 /home/ansadmin/.ssh/authorized_keys",
    ]
  }
  lifecycle {
    ignore_changes = [ami, root_block_device[0].volume_type]
    prevent_destroy = false
  }
}
# =============================================================================
# 4. PROMETHEUS - Monitoring Server
# =============================================================================
resource "aws_instance" "prometheus" {
  depends_on = [aws_security_group_rule.prometheus_egress_all]
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg_prometheus.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.this.key_name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    delete_on_termination = true
    encrypted = true
    tags = {
      Name = "${local.name_prefix}-prometheus-root-vol"
    }
  }
  tags = {
    Name = "${local.name_prefix}-prometheus-server"
    Role = "prometheus"
  }
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = tls_private_key.this.private_key_pem
    timeout = "10m"
  }
  provisioner "file" {
    source = "${path.module}/scripts/ansible-managed.sh"
    destination = "/home/ubuntu/ansible-managed.sh"
  }
  provisioner "file" {
    source = "${path.module}/keys/id_rsa.pub"
    destination = "/home/ubuntu/id_rsa.pub"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo bash /home/ubuntu/ansible-managed.sh",
      "sudo tee -a /home/ansadmin/.ssh/authorized_keys < /home/ubuntu/id_rsa.pub",
      "sudo rm '/home/ubuntu/id_rsa.pub'",
      "sudo chown ansadmin:ansadmin /home/ansadmin/.ssh/authorized_keys",
      "sudo chmod 600 /home/ansadmin/.ssh/authorized_keys",
    ]
  }
  lifecycle {
    ignore_changes = [ami, root_block_device[0].volume_type]
    prevent_destroy = false
  }
}
# =============================================================================
# 5. ANSIBLE - Ansible Controller (created after all other instances)
# =============================================================================
resource "aws_instance" "ansible" {
  depends_on = [
    aws_security_group_rule.ansible_egress_all,
    aws_instance.master,
    aws_instance.worker,
    aws_instance.haproxy,
    aws_instance.prometheus,
  ]
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg_ansible.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.this.key_name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    delete_on_termination = true
    encrypted = true
    tags = {
      Name = "${local.name_prefix}-ansible-controller-root-vol"
    }
  }
  tags = {
    Name = "${local.name_prefix}-ansible-controller"
    Role = "ansible-controller"
  }
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = tls_private_key.this.private_key_pem
    timeout = "10m"
  }
  # PROVISIONER 1: Create ansadmin user
  provisioner "remote-exec" {
    inline = [
      "sudo useradd -m -s /bin/bash ansadmin || echo 'user already exists'",
      "sudo mkdir -p /home/ansadmin/.ssh",
      "sudo chown -R ansadmin:ansadmin /home/ansadmin/.ssh",
      "sudo chmod 700 /home/ansadmin/.ssh",
    ]
  }
  # PROVISIONER 2: Copy SSH keys
  provisioner "file" {
    source = "${path.module}/keys/id_rsa"
    destination = "/tmp/id_rsa"
  }
  provisioner "file" {
    source = "${path.module}/keys/id_rsa.pub"
    destination = "/tmp/id_rsa.pub"
  }
  # PROVISIONER 3: Upload ansible-controller.sh bootstrap script
  provisioner "file" {
    source = "${path.module}/scripts/ansible-controller.sh"
    destination = "/home/ubuntu/ansible-controller.sh"
  }
  # PROVISIONER 4: Generate /etc/ansible/hosts dynamically
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/ansible",
      "sudo tee /etc/ansible/hosts > /dev/null <<'INVENTORY_EOF'",
      "# Ansible Inventory - Generated by Terraform",
      "# DO NOT EDIT MANUALLY",
      "",
      "[haproxy]",
      "${join("\n", [for key, inst in aws_instance.haproxy : inst.private_ip])}",
      "",
      "[masters]",
      "${join("\n", [for key, inst in aws_instance.master : inst.private_ip])}",
      "",
      "[workers]",
      "${join("\n", [for key, inst in aws_instance.worker : inst.private_ip])}",
      "",
      "[prometheus]",
      "${aws_instance.prometheus.private_ip}",
      "",
      "[k8s_cluster:children]",
      "masters",
      "workers",
      "",
      "[all:vars]",
      "ansible_python_interpreter=/usr/bin/python3",
      "INVENTORY_EOF",
    ]
  }
  # PROVISIONER 5: Fix permissions + run controller script
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/id_rsa /home/ansadmin/.ssh/id_rsa",
      "sudo mv /tmp/id_rsa.pub /home/ansadmin/.ssh/id_rsa.pub",
      "sudo chown ansadmin:ansadmin /home/ansadmin/.ssh/id_rsa /home/ansadmin/.ssh/id_rsa.pub",
      "sudo chmod 600 /home/ansadmin/.ssh/id_rsa",
      "sudo chmod 644 /home/ansadmin/.ssh/id_rsa.pub",
      "sudo bash /home/ubuntu/ansible-controller.sh",
    ]
  }
  lifecycle {
    ignore_changes = [ami, root_block_device[0].volume_type]
    prevent_destroy = false
  }
}
# =============================================================================
# 6. LOCAL FILE: Ansible inventory (local copy for reference)
# =============================================================================
resource "local_file" "ansible_hosts" {
  content = templatefile("${path.module}/templates/hosts.tpl", {
    haproxy_ips = [for key, inst in aws_instance.haproxy : inst.private_ip]
    master_ips = [for key, inst in aws_instance.master : inst.private_ip]
    worker_ips = [for key, inst in aws_instance.worker : inst.private_ip]
    prometheus_ip = aws_instance.prometheus.private_ip
  })
  filename = "${path.module}/generated/hosts"
  file_permission = "0644"
}
# =============================================================================
# EC2 INSTANCES - Complete!
#
# Creation order:
#   1. master + worker           - Parallel (no inter-dependency)
#   2. haproxy                   - After master (needs master IPs for config)
#   3. prometheus                - After master + worker (needs IPs for targets)
#   4. ansible                   - After ALL others (needs all IPs for inventory)
#
# Dynamic private IPs (auto-assigned from subnet). SG-to-SG inter-node traffic.
# =============================================================================
