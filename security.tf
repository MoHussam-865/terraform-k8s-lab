# =============================================================================
# FILE:        security.tf
# PURPOSE:     Define per-role Security Groups for the enhanced Kubernetes lab.
# LOADED:      At plan time. SGs are just configuration until attached to an EC2.
# OPTIONAL:    No. EC2 API requires at least one SG per instance launch.
# DEPENDS ON:  networking.tf (references aws_vpc.main.id), variables.tf
# =============================================================================

# =============================================================================
# KEY DESIGN DECISIONS
# 1. PER-ROLE SGs: each role has its own SG with minimum rules (least privilege).
# 2. SG-TO-SG REFERENCES: inter-node traffic uses source_security_group_id.
# 3. CIDR BLOCKS only for: 0.0.0.0/0 (SSH, admin, NodePort, egress).
# 4. STATEFUL: response traffic is automatically allowed.
# =============================================================================

# =============================================================================
# 1. SG_ANSIBLE - Ansible Controller
# =============================================================================
resource "aws_security_group" "sg_ansible" {
  name = "${local.name_prefix}-sg-ansible"
  description = "Ansible controller: SSH inbound only"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-sg-ansible" }
}

resource "aws_security_group_rule" "ansible_ingress_ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_ansible.id
  description = "Allow SSH from anywhere"
}

resource "aws_security_group_rule" "ansible_egress_all" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_ansible.id
  description = "Allow all outbound traffic"
}

# =============================================================================
# 2. SG_HAPROXY - HAProxy Load Balancer
# =============================================================================
resource "aws_security_group" "sg_haproxy" {
  name = "${local.name_prefix}-sg-haproxy"
  description = "HAProxy LB: SSH + K8s API (6443) inbound"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-sg-haproxy" }
}

resource "aws_security_group_rule" "haproxy_ingress_ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_haproxy.id
  description = "Allow SSH from anywhere"
}

resource "aws_security_group_rule" "haproxy_ingress_k8s_api" {
  type = "ingress"
  from_port = 6443
  to_port = 6443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_haproxy.id
  description = "Allow kubectl to K8s API via HAProxy :6443"
}

resource "aws_security_group_rule" "haproxy_egress_k8s_api" {
  type = "egress"
  from_port = 6443
  to_port = 6443
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_haproxy.id
  description = "Forward K8s API traffic to master nodes"
}

resource "aws_security_group_rule" "haproxy_egress_all" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_haproxy.id
  description = "Allow all outbound traffic"
}

# =============================================================================
# 3. SG_MASTER - Kubernetes Control Plane Nodes
# =============================================================================
resource "aws_security_group" "sg_master" {
  name = "${local.name_prefix}-sg-master"
  description = "K8s master nodes: control plane services"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-sg-master" }
}

resource "aws_security_group_rule" "master_ingress_ssh_from_ansible" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_ansible.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow SSH from Ansible controller"
}

resource "aws_security_group_rule" "master_ingress_k8s_api_from_haproxy" {
  type = "ingress"
  from_port = 6443
  to_port = 6443
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_haproxy.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow K8s API from HAProxy"
}

resource "aws_security_group_rule" "master_ingress_k8s_api_from_master" {
  type = "ingress"
  from_port = 6443
  to_port = 6443
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow inter-master K8s API"
}

resource "aws_security_group_rule" "master_ingress_etcd" {
  type = "ingress"
  from_port = 2379
  to_port = 2380
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow etcd peer communication"
}

resource "aws_security_group_rule" "master_ingress_kubelet_from_master" {
  type = "ingress"
  from_port = 10250
  to_port = 10250
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow kubelet API between masters"
}

resource "aws_security_group_rule" "master_ingress_kubelet_from_worker" {
  type = "ingress"
  from_port = 10250
  to_port = 10250
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_worker.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow kubelet API from workers"
}

resource "aws_security_group_rule" "master_ingress_controller_manager" {
  type = "ingress"
  from_port = 10257
  to_port = 10257
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow Controller Manager"
}

resource "aws_security_group_rule" "master_ingress_scheduler" {
  type = "ingress"
  from_port = 10259
  to_port = 10259
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow Scheduler"
}

resource "aws_security_group_rule" "master_ingress_node_exporter" {
  type = "ingress"
  from_port = 9100
  to_port = 9100
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_prometheus.id
  security_group_id = aws_security_group.sg_master.id
  description = "Allow Prometheus to scrape :9100"
}

resource "aws_security_group_rule" "master_egress_all" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_master.id
  description = "Allow all outbound traffic"
}

# =============================================================================
# 4. SG_WORKER - Kubernetes Worker Nodes
# =============================================================================
resource "aws_security_group" "sg_worker" {
  name = "${local.name_prefix}-sg-worker"
  description = "K8s worker nodes: kubelet + NodePort + metrics"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-sg-worker" }
}

resource "aws_security_group_rule" "worker_ingress_ssh_from_ansible" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_ansible.id
  security_group_id = aws_security_group.sg_worker.id
  description = "Allow SSH from Ansible controller"
}

resource "aws_security_group_rule" "worker_ingress_kubelet_from_master" {
  type = "ingress"
  from_port = 10250
  to_port = 10250
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_worker.id
  description = "Allow kubelet from masters"
}

resource "aws_security_group_rule" "worker_ingress_nodeport" {
  type = "ingress"
  from_port = 30000
  to_port = 32767
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_worker.id
  description = "Allow NodePort services (K8s workloads)"
}

resource "aws_security_group_rule" "worker_ingress_node_exporter" {
  type = "ingress"
  from_port = 9100
  to_port = 9100
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_prometheus.id
  security_group_id = aws_security_group.sg_worker.id
  description = "Allow Prometheus to scrape :9100"
}

resource "aws_security_group_rule" "worker_egress_all" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_worker.id
  description = "Allow all outbound traffic"
}

# =============================================================================
# 5. SG_PROMETHEUS - Prometheus & Grafana Monitoring Server
# =============================================================================
resource "aws_security_group" "sg_prometheus" {
  name = "${local.name_prefix}-sg-prometheus"
  description = "Prometheus (+Grafana) monitoring server"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-sg-prometheus" }
}

resource "aws_security_group_rule" "prometheus_ingress_ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Allow SSH from anywhere"
}

resource "aws_security_group_rule" "prometheus_ingress_web_ui" {
  type = "ingress"
  from_port = 9090
  to_port = 9090
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Allow Prometheus web UI (:9090)"
}

resource "aws_security_group_rule" "prometheus_ingress_grafana" {
  type = "ingress"
  from_port = 3000
  to_port = 3000
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Allow Grafana web UI (:3000)"
}

resource "aws_security_group_rule" "prometheus_egress_scrape_masters" {
  type = "egress"
  from_port = 9100
  to_port = 9100
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_master.id
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Scrape Node Exporter on masters"
}

resource "aws_security_group_rule" "prometheus_egress_scrape_workers" {
  type = "egress"
  from_port = 9100
  to_port = 9100
  protocol = "tcp"
  source_security_group_id = aws_security_group.sg_worker.id
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Scrape Node Exporter on workers"
}

resource "aws_security_group_rule" "prometheus_egress_all" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_prometheus.id
  description = "Allow all outbound traffic"
}

# =============================================================================
# SECURITY GROUPS COMPLETE!
# Summary:
#   1. sg_ansible    - Ansible controller (SSH inbound only)
#   2. sg_haproxy    - HAProxy LB (SSH + 6443 inbound, 6443 to masters)
#   3. sg_master     - K8s control plane (multi-port, SG refs for inter-node)
#   4. sg_worker     - K8s workers (SSH from ansible, 10250 from masters, NodePort)
#   5. sg_prometheus - Prometheus+Grafana (SSH + 9090 + 3000 inbound, scrapes :9100)
# All inter-node traffic uses SG-to-SG references, not CIDR blocks.
# =============================================================================