# Terraform K8s Lab — Enhancement Plan

## 📋 Executive Summary

This document outlines the transformation of the current 4-instance Kubernetes lab into a **production-grade, scalable, multi-tier Kubernetes infrastructure** on AWS. The new design introduces security hardening through per-role security groups, high availability with a load-balanced control plane, observability with Prometheus monitoring, and full scalability to add masters and workers dynamically.

---

## 🎯 Goals

| # | Goal | Current State | Target State |
|---|------|--------------|--------------|
| 1 | **Dynamic IP Allocation** | Fixed private IPs hardcoded in `variables.tf` + `locals.tf` | AWS auto-assigns IPs from subnet; Terraform outputs capture them |
| 2 | **Ansible Hosts File** | Output-based `hosts.ini` with only 3 managed nodes | Automatically generated `hosts` file with all groups (masters, workers, haproxy, prometheus) using `local_file` resource |
| 3 | **HAProxy Load Balancer** | Not present (control-plane single point of failure) | 1 HAProxy instance load-balancing TCP 6443 across all 3 master nodes |
| 4 | **3 Master Nodes** | 1 control-plane-01 | 3 control-plane nodes (master-01, master-02, master-03) for HA control plane |
| 5 | **Prometheus Monitoring** | Not present | 1 Prometheus server scraping Node Exporter metrics from all masters and workers |
| 6 | **Scalability** | Fixed 4-instance map in `locals.tf` | Variable-driven instance counts (`master_count`, `worker_count`) with `for_each` using `range()`; add nodes by changing a number |
| 7 | **Per-Role Security Groups** | 1 monolithic SG for everything | 5 dedicated SGs with SG-to-SG references (no CIDR-based source for inter-node traffic) |
---

## 🏗️ Target Architecture

```
Internet
    ↓
Internet Gateway
    ↓
Route Table (0.0.0.0/0 → IGW)
    ↓
VPC (10.1.0.0/24)
    ↓
Public Subnet (10.1.0.0/26)      ← expanded from /28 → /26 (64 IPs, 59 usable)
    |
    ├─ [sg_ansible] ───────────── ansible-controller (dynamic IP)
    |
    ├─ [sg_haproxy] ───────────── haproxy-lb (dynamic IP) ──→ TCP 6443 to sg_master
    |
    ├─ [sg_master] ────────────── master-01 (dynamic IP)
    │                             master-02 (dynamic IP)
    │                             master-03 (dynamic IP)
    │                                ├── etcd:2379-2380 (master-to-master)
    │                                ├── kubelet:10250 (master & worker)
    │                                ├── controller-manager:10257
    │                                └── scheduler:10259
    |
    ├─ [sg_worker] ────────────── worker-01 (dynamic IP)
    │                             worker-02 (dynamic IP)
    │                             ... worker-N  (scalable via var.worker_count)
    │                                └── NodePort:30000-32767
    |
    └─ [sg_prometheus] ────────── prometheus-server (dynamic IP)
                                     └── scrapes :9100 on masters & workers

Key: [] = security group boundary, ─→ = allowed traffic direction
```

---

## 🔐 Security Group Matrix (Detailed)

### 1. `sg_ansible` — Ansible Controller

| Direction | Port | Source/Destination | Reason |
|-----------|------|--------------------|--------|
| **Inbound** | 22 (SSH) | `var.my_public_ip` | Your SSH into Ansible controller |
| **Inbound** | 9100 | `sg_prometheus` (SG reference) | Node Exporter metrics scraped by Prometheus |
| **Outbound** | ALL | 0.0.0.0/0 | SSH to nodes, apt, git clone, K8s installs |

### 2. `sg_haproxy` — HAProxy Load Balancer

| Direction | Port | Source/Destination | Reason |
|-----------|------|--------------------|--------|
| **Inbound** | 22 (SSH) | `var.my_public_ip` | Administration |
| **Inbound** | 6443 | `var.my_public_ip` | kubectl / kubeadm endpoint |
| **Inbound** | 9100 | `sg_prometheus` (SG reference) | Node Exporter metrics scraped by Prometheus |
| **Outbound** | 6443 | `sg_master` (SG reference) | Forward traffic to K8s API servers |

### 3. `sg_master` — Kubernetes Control Plane

| Direction | Port | Source/Destination | Reason |
|-----------|------|--------------------|--------|
| **Inbound** | 22 (SSH) | `sg_ansible` (SG reference) | Ansible configures masters |
| **Inbound** | 6443 | `sg_haproxy` (SG reference) | HAProxy forwards K8s API traffic |
| **Inbound** | 6443 | `sg_master` (SG self-reference) | Inter-master API communication |
| **Inbound** | 2379-2380 | `sg_master` (SG self-reference) | etcd peer communication |
| **Inbound** | 10250 | `sg_master` (SG self-reference) | kubelet API (master-to-master) |
| **Inbound** | 10250 | `sg_worker` (SG reference) | kubelet communication from workers |
| **Inbound** | 10257 | `sg_master` (SG self-reference) | Controller Manager |
| **Inbound** | 10259 | `sg_master` (SG self-reference) | Scheduler |
| **Inbound** | 9100 | `sg_prometheus` (SG reference) | Node Exporter metrics scraped by Prometheus |
| **Outbound** | ALL | 0.0.0.0/0 | Package downloads, Docker pulls, etc. |

### 4. `sg_worker` — Kubernetes Workers

| Direction | Port | Source/Destination | Reason |
|-----------|------|--------------------|--------|
| **Inbound** | 22 (SSH) | `sg_ansible` (SG reference) | Ansible configures workers |
| **Inbound** | 10250 | `sg_master` (SG reference) | kubelet API from control plane |
| **Inbound** | 30000-32767 | 0.0.0.0/0 (optional) | NodePort services |
| **Inbound** | 9100 | `sg_prometheus` (SG reference) | Node Exporter metrics scraped by Prometheus |
| **Outbound** | ALL | 0.0.0.0/0 | Package downloads, Docker pulls, etc. |

### 5. `sg_prometheus` — Prometheus Monitoring Server

| Direction | Port | Source/Destination | Reason |
|-----------|------|--------------------|--------|
| **Inbound** | 22 (SSH) | `var.my_public_ip` | Administration |
| **Inbound** | 9090 | `var.my_public_ip` | Prometheus web UI |
| **Outbound** | 9100 | `sg_master` (SG reference) | Scrape master Node Exporters |
| **Outbound** | 9100 | `sg_worker` (SG reference) | Scrape worker Node Exporters |
| **Outbound** | 9100 | `sg_haproxy` (SG reference) | Scrape HAProxy Node Exporters |
| **Outbound** | 9100 | `sg_ansible` (SG reference) | Scrape Ansible controller Node Exporters |
| **Outbound** | ALL | 0.0.0.0/0 | apt, internet access |
### SG Relationship Diagram

```
                    YOUR PUBLIC IP (var.my_public_ip)
                   /           |            \
                  /            |             \
            SSH:22          SSH:22         SSH:22+9090
                |               |                |
          [sg_ansible]     [sg_haproxy]    [sg_prometheus]
                |               |                |
                |22            |6443            |9100 (scrape)
                |               |                |
        ┌───────┴───────────────┼────────────────┴──────────┐
        |                       |                            |
    [sg_master]  ←──6443── [sg_haproxy]              [sg_worker]
        |  ↑                                                  ↑
        |  └────── 10250 ─────────────────────────────────────┘
        |  ┌────── 2379-2380 (etcd) ─────────────────┐
        └──┤ 6443, 10250, 10257, 10259 (self)       │
           └─────────────────────────────────────────┘
                           master-to-master

    Notes:
    - SG references (not CIDRs) for all inter-node traffic
    - Prometheus scrapes :9100 from both sg_master and sg_worker
    - HAProxy ONLY talks to sg_master:6443 (principle of least privilege)
```

---

## 🔄 Subnet Expansion

**Current**: `10.1.0.0/28` = 16 IPs, 11 usable (after AWS reserves 5)

**Problem**: New architecture requires at minimum:
- 1 ansible-controller
- 1 haproxy-lb
- 3 master nodes
- 2 worker nodes (minimum, scalable)
- 1 prometheus-server
= **8 instances minimum**, plus room for scaling

**Solution**: `10.1.0.0/26` = 64 IPs, 59 usable
- Accommodates ~50+ instances
- Same VPC (10.1.0.0/24), just wider subnet mask
- No IP collision issues
---

## 📐 File Changes Breakdown — Phase by Phase

### Phase 1: Variables & Locals Restructuring

**Files to modify**: `variables.tf`, `locals.tf`

| Change | Why |
|--------|-----|
| Remove `var.private_ips` (the hardcoded IP map) | Goal #1: dynamic IPs |
| Add `var.my_public_ip` (string, required, no default) | Goal #7: restrict SSH to YOUR IP only |
| Add `var.master_count` (number, default 3, odd-only validation) | Goal #4, #6: scalable masters with etcd quorum |
| Add `var.worker_count` (number, default 2) | Goal #6: scalable workers |
| Add `var.haproxy_count` (number, default 1) | Goal #3: HAProxy count (kept at 1 but scalable) |
| Update `var.subnet_cidr` default from `10.1.0.0/28` to `10.1.0.0/26` | More IP capacity |
| Remove `local.instances` and `local.managed_instances` | Replaced by dynamic for_each with range() |
| Add inventory-related locals for hosts file template data | Goal #2 |

**Validation additions**:
- `my_public_ip` must be a valid CIDR (e.g., `203.0.113.5/32`)
- `master_count` must be odd (1, 3, 5, 7) for etcd quorum
- `worker_count` minimum 1
- Total instances must fit within /26 subnet capacity (~59 usable)

---

### Phase 2: Networking Expansion

**Files to modify**: `networking.tf`

| Change | Why |
|--------|-----|
| Subnet CIDR `/28` → `/26` (64 IPs, 59 usable) | Accommodate 8+ instances with room to grow |
| **No other networking changes needed** | VPC, IGW, Route Table, Association remain identical
---

### Phase 3: Security Groups — Complete Rewrite

**Files to modify**: `security.tf` (will be significantly rewritten)

| Change | Why |
|--------|-----|
| Remove monolithic `aws_security_group.k8s_lab` + its 3 inline rules | Replaced by 5 per-role SGs + ~25 separate rule resources |
| Create `aws_security_group.sg_ansible` | Isolated SG for Ansible controller |
| Create `aws_security_group.sg_haproxy` | Isolated SG for HAProxy LB |
| Create `aws_security_group.sg_master` | Isolated SG for K8s control plane |
| Create `aws_security_group.sg_worker` | Isolated SG for K8s workers |
| Create `aws_security_group.sg_prometheus` | Isolated SG for monitoring |

**Design Pattern**: SG-to-SG references (NOT CIDRs) for inter-node traffic:
- `source_security_group_id = aws_security_group.sg_ansible.id`
- Self-referencing: `source_security_group_id = aws_security_group.sg_master.id`
- CIDRs only for: `var.my_public_ip/32` (SSH, Prometheus UI, kubectl) and `0.0.0.0/0` (NodePort, egress)

**Rule Count**:

| SG | Ingress Rules | Egress Rules |
|----|--------------|--------------|
| sg_ansible | 1 (SSH from my IP) | 1 (all out) |
| sg_haproxy | 2 (SSH + 6443 from my IP) | 1 (6443 to sg_master) |
| sg_master | 8 (SSH, 6443x2, 2379-80, 10250x2, 10257, 10259, 9100) | 1 (all out) |
| sg_worker | 4 (SSH, 10250, 30000-32767, 9100) | 1 (all out) |
| sg_prometheus | 2 (SSH + 9090 from my IP) | 3 (9100 to masters, 9100 to workers, all out) |

**Key point**: sg_master has 2 distinct port 10250 rules:
- One with `source_security_group_id = sg_master` (master-to-master kubelet)
- One with `source_security_group_id = sg_worker` (worker-to-master kubelet)
---

### Phase 4: EC2 Instances — Dynamic & Scalable

**Files to modify**: `ec2.tf` (will be significantly restructured)

**Current approach**: Single `aws_instance.managed` with `for_each` over hardcoded `local.managed_instances` map + separate singleton `aws_instance.ansible_controller`.

**New approach**: Per-role resource blocks, each using `for_each` over `toset(range(N))`:

```hcl
resource "aws_instance" "master" {
  for_each = toset(range(var.master_count)) # N=3 → {"0","1","2"}

  tags = {
    Name = "${local.name_prefix}-master-${format("%02d", each.key + 1)}"
    Role = "control-plane"
  }
  vpc_security_group_ids = [aws_security_group.sg_master.id]
  # NO private_ip — AWS auto-assigns from subnet
}
```

| Resource Block | for_each | SG Attached | Default |
|---------------|----------|-------------|---------|
| aws_instance.ansible | Singleton (no for_each) | sg_ansible | 1 |
| aws_instance.haproxy | toset(range(var.haproxy_count)) | sg_haproxy | 1 |
| aws_instance.master | toset(range(var.master_count)) | sg_master | 3 |
| aws_instance.worker | toset(range(var.worker_count)) | sg_worker | 2 |
| aws_instance.prometheus | Singleton (no for_each) | sg_prometheus | 1 |

**Key changes**:
- Remove `private_ip` from ALL instance definitions → AWS auto-assigns
- Remove `local.instances` and `local.managed_instances` → use range()
- `depends_on` between haproxy and masters (haproxy config needs master IPs)
- Ansible controller: Upload dynamically generated `/etc/ansible/hosts` instead of hardcoded IPs in bootstrap script
- Each `root_block_device` gets role-specific volume Name tags

---

### Phase 5: Ansible Hosts File Generation

**Files to create**: `templates/hosts.tpl`, add `local_file` resource in ec2.tf

**Goal #2**: Generate `/etc/ansible/hosts` dynamically using `templatefile()`.

```hcl
resource "local_file" "ansible_hosts" {
  content = templatefile("${path.module}/templates/hosts.tpl", {
    haproxy_ip    = [for i, inst in aws_instance.haproxy : inst.private_ip]
    master_ips    = [for i, inst in aws_instance.master : inst.private_ip]
    worker_ips    = [for i, inst in aws_instance.worker : inst.private_ip]
    prometheus_ip = aws_instance.prometheus.private_ip
  })
  filename = "${path.module}/generated/hosts"
}
```

Uploaded to ansible controller via `file` provisioner. Template uses `%{ for ip in ... ~}${ip} ...%{ endfor ~}` for dynamic lists.

---

### Phase 6: Outputs Update

**Files to modify**: `outputs.tf`

| Change | Why |
|--------|-----|
| Remove all hardcoded references like `aws_instance.managed["control-plane-01"]` | Instances now dynamic per-role |
| Split outputs by role: `ansible_ip`, `haproxy_ips`, `master_ips`, `worker_ips`, `prometheus_ip` | Clearer consumption |
| Update `ansible_inventory` output to pull from new instance resources | Match new architecture |
| Add `ansible_inventory_path` output | Points to local_file path |

---

### Phase 7: Bootstrap Scripts Update

**Files to modify**: `scripts/ansible-controller.sh`

| Change | Why |
|--------|-----|
| Remove hardcoded IPs from `/etc/ansible/hosts` creation block | Terraform now generates + uploads hosts file |
| Script now copies uploaded file: `sudo cp /home/ubuntu/hosts /etc/ansible/hosts` | Cleaner separation of concerns |
| **ansible-managed.sh**: No changes needed | Masters & workers still get same ansadmin + SSH setup |
---

### Phase 8: Template Files (New)

**Files to create**: `templates/` directory

| File | Purpose |
|------|---------|
| `templates/hosts.tpl` | Ansible inventory template with for-loops for master/worker IPs |
| `templates/haproxy.cfg.tpl` | HAProxy config with backend servers = all master private IPs on :6443 |
| (Optional) `templates/prometheus.yml.tpl` | Prometheus scrape config targeting all masters + workers on :9100 |

---

### Phase 9: Documentation & Config Update

**Files to modify**: `README.md`, `terraform.tfvars.example`, `.gitignore`

| Change | Why |
|--------|-----|
| Update README architecture diagram | Reflect 8+ instance design |
| Update security section in README | 5 SGs instead of 1 |
| Update cost estimate | More instances |
| Add `my_public_ip` to `.tfvars.example` | Required variable with no default |
| Add `master_count`, `worker_count` to `.tfvars.example` | Show scalable variables |
| Add `generated/` directory to `.gitignore` | Generated hosts file shouldn't be committed |
---

## 📊 Resource Count Comparison

| Resource Type | Current | Target | Delta |
|--------------|---------|--------|-------|
| aws_vpc | 1 | 1 | 0 |
| aws_subnet | 1 | 1 | 0 |
| aws_internet_gateway | 1 | 1 | 0 |
| aws_route_table | 1 | 1 | 0 |
| aws_route | 1 | 1 | 0 |
| aws_route_table_association | 1 | 1 | 0 |
| aws_security_group | 1 | 5 | +4 |
| aws_security_group_rule | 3 | ~25 | +22 |
| aws_instance resource blocks | 2 | 5 | +3 |
| aws_key_pair | 1 | 1 | 0 |
| tls_private_key | 1 | 1 | 0 |
| local_file (private key) | 1 | 1 | 0 |
| local_file (ansible hosts) | 0 | 1 | +1 |
| data.aws_availability_zones | 1 | 1 | 0 |
| data.aws_ami | 1 | 1 | 0 |
| **Total managed resources** | ~14 | ~42 | ~+28 |

**Instance count**: 4 → 8 (at defaults: 1 ansible + 1 haproxy + 3 masters + 2 workers + 1 prometheus)

---

## 🧠 Design Decisions & Trade-offs

### Why `for_each` with `range()` instead of `count`?

- `count`: Instances indexed as `[0]`, `[1]`, `[2]`. Removing index 0 forces Terraform to shift all indices → all instances destroyed and recreated.
- `range()` + `for_each`: Instances indexed by stable string keys `["0"]`, `["1"]`, `["2"]`. Removing key `"0"` only destroys that ONE instance. Others stay untouched.
- This is the critical property that enables **scalability** (Goal #6).

### Why 5 separate security groups?

- **Least privilege**: Ansible only needs SSH. HAProxy only needs 6443. Prometheus only needs 9090 + scrape targets. A monolithic SG forces all instances to share the union of all rules.
- **SG-to-SG references**: "Allow traffic FROM sg_master" is self-documenting and auto-updates when instances change (no CIDR maintenance).
- **Auditability**: AWS Console clearly shows which rules apply to which instance role.

### Why dynamic IPs instead of fixed?

- **Simplicity**: No manual IP management. AWS auto-assigns within subnet.
- **Scalability**: Adding a 4th master doesn't require picking an unused IP.
- **Ansible works fine**: The hosts file is generated dynamically by Terraform from actual private_ip attributes, so Ansible always has correct addresses.

### Why `/26` subnet?

- `/28` = 11 usable → not enough for 8+ instances
- `/26` = 59 usable → ~50 instance capacity
- `/27` (27 usable) would also work but with less headroom
- Stays within the same VPC CIDR (10.1.0.0/24)

### Why HAProxy and not AWS NLB?

- **Cost**: HAProxy on t3.small (~$15/month) vs NLB (~$22/month + LCU charges)
- **Learning**: Understanding HAProxy is valuable DevOps knowledge
- **Trade-off**: NLB is fully managed (no EC2 to patch). For a lab, HAProxy is the right educational choice.

---

## ⚠️ Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SG rule limit (60 in/60 out per SG) | Can't add rules | sg_master has ~8 rules — well within limits |
| Subnet CIDR change requires destroy/recreate | All resources lost | Must `terraform destroy` old infra first, then rebuild |
| `var.my_public_ip` changes (DHCP) | Locked out of SSH | Keep a separate override mechanism or use SSM as backup |
| 3-node etcd — losing 2 nodes = outage | Cluster down | Acceptable for lab. Production = 5 nodes across 3 AZs |
| HAProxy single point of failure | kubectl unreachable if HAProxy dies | Acceptable for lab. Production = HAProxy pair + keepalived or NLB |
---

## 📅 Implementation Order (Recommended)

| Step | Task | Dependencies |
|------|------|-------------|
| **Step 1** | Update `variables.tf` — add new vars, remove `private_ips`, add validations | None |
| **Step 2** | Update `locals.tf` — remove instance map, add inventory helpers | variables.tf |
| **Step 3** | Update `networking.tf` — expand subnet to `/26` | None |
| **Step 4** | Rewrite `security.tf` — 5 SGs, ~25 rules, all SG-to-SG references | networking.tf |
| **Step 5** | Rewrite `ec2.tf` — 5 resource blocks, dynamic for_each, per-role SGs, no private_ip | security.tf |
| **Step 6** | Create `templates/hosts.tpl` + add `local_file` for hosts generation | ec2.tf |
| **Step 7** | Update `outputs.tf` — role-based dynamic outputs | ec2.tf |
| **Step 8** | Update `scripts/ansible-controller.sh` — remove hardcoded IPs | ec2.tf |
| **Step 9** | Update `terraform.tfvars.example` | variables.tf |
| **Step 10** | Update `README.md` — new architecture, variables, commands | All |
| **Step 11** | Validation: `terraform init`, `terraform validate`, `terraform fmt`, `terraform plan` | All |
| **Step 12** | (Optional) Test apply on fresh AWS account | All |

---

## ✅ Acceptance Criteria

- [ ] `var.my_public_ip` is required; no default — user must explicitly provide it
- [ ] All 8+ instances receive dynamic private IPs from AWS (no hardcoded IPs)
- [ ] HAProxy forwards TCP 6443 to all 3 master nodes
- [ ] `terraform output -raw ansible_inventory > hosts.ini` produces a valid Ansible inventory file
- [ ] Adding `master_count = 5` in terraform.tfvars creates 5 masters without destroying existing ones
- [ ] Adding `worker_count = 4` creates 2 new workers without touching existing ones
- [ ] Each instance only has the security group rules relevant to its role
- [ ] SG inter-node rules use SG references (source_security_group_id), not CIDRs
- [ ] Prometheus can scrape port 9100 from all masters, workers, HAProxy, and Ansible controller
- [ ] `terraform validate` passes with no errors
- [ ] `terraform plan` shows the expected ~42 resources
- [ ] `terraform fmt -recursive` shows no diffs (code is consistently formatted)

---

*Plan created: 2026-11-07 | Version: 1.0*