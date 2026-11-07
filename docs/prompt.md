
# I want you to act as a **Senior DevOps Engineer, AWS Solutions Architect, Terraform expert, and Terraform instructor.**

Your goal is **NOT just to generate Terraform code.**

Your goal is to teach me how a real Infrastructure-as-Code (IaC) project is designed while building it from scratch, exactly as an experienced DevOps engineer would.

Treat this as writing an entire hands-on Terraform course while building a real AWS infrastructure.

---

# About Me

I am a software engineer with programming experience.

I already understand:

- Linux
- SSH
- AWS basics
- Docker
- Kubernetes basics
- Ansible
- Networking basics
- CIDR
- Security Groups
- VPC
- EC2

I have already built an Ansible project that provisions a Kubernetes cluster.

Now I want to learn **Terraform properly**, not just copy Terraform code.

I learn best by reading large, real-world projects with detailed comments.

---

# My Goal

Build a complete Terraform project that provisions the AWS infrastructure needed for my Kubernetes lab.

The infrastructure should include:

- 1 VPC
- CIDR: 10.1.0.0/24

Inside it:

- 1 Public Subnet
- CIDR: 10.1.0.0/28

Networking:

- Internet Gateway
- Route Table
- Route Table Association

Security:

One Security Group

Inbound:

- SSH (22)
- Kubernetes API Server (6443)

Outbound:

- Allow all traffic

Compute:

Four Ubuntu EC2 instances.

Names:

- ansible-controller
- control-plane-01
- worker-01
- worker-02

Instance type:

t3.small

Each instance should:

- Receive a public IPv4 address
- Belong to the subnet
- Belong to the security group
- Use a Key Pair for SSH

Private IPs should be fixed:

10.1.0.6   worker-01

10.1.0.7   ansible-controller

10.1.0.8   worker-02

10.1.0.10  control-plane-01

The Ansible controller is NOT part of Kubernetes.

It only manages the other three servers.

---

# Final Architecture

Internet

↓

Internet Gateway

↓

Route Table

↓

VPC (10.1.0.0/24)

↓

Subnet (10.1.0.0/28)

↓

Security Group

↓

EC2

- ansible-controller
- control-plane-01
- worker-01
- worker-02

Later, Ansible will connect over SSH and build the Kubernetes cluster.

Terraform's ONLY responsibility is creating the AWS infrastructure.

---

# Repository Structure

Show me how a professional Terraform repository should be organized.

For example:

terraform-k8s-lab/

provider.tf

versions.tf

variables.tf

outputs.tf

locals.tf

networking.tf

security.tf

ec2.tf

terraform.tfvars.example

README.md

.gitignore

If additional files belong in a production project, include them and explain why.

---

# VERY IMPORTANT

Do NOT simply generate code.

For every folder explain:

- Why it exists.
- When professionals use it.
- What belongs inside it.
- What should NOT go inside it.

For every file explain:

- Why it exists.
- When Terraform loads it.
- Whether it is optional.
- Which other files depend on it.
- Why it is separated into its own file.

---

# Code Requirements

Generate every file one by one.

For every file:

1. Show its full path.

Example:

networking.tf

2. Explain its purpose.

3. Show the complete Terraform code.

4. Add detailed comments throughout the code.

Explain every important block including:

- resource
- data
- provider
- variable
- output
- locals
- module
- lifecycle
- provisioner (if used)
- depends_on

Explain every argument.

Pretend I have never seen professional Terraform before.

---

# Build the project in stages

Do NOT generate everything at once.

Build it step by step.

Stage 1

Design the repository structure.

Explain every folder and file.

No Terraform code yet.

---

Stage 2

Create versions.tf

Explain:

- required_version
- required_providers
- why versions are pinned

---

Stage 3

Create provider.tf

Explain:

- provider
- authentication
- AWS region
- credentials
- why providers exist

---

Stage 4

Create variables.tf

Explain:

- variables
- types
- defaults
- validation
- descriptions
- why hardcoding values is bad

---

Stage 5

Create locals.tf

Explain:

- when locals are useful
- naming conventions
- avoiding duplicated values

---

Stage 6

Create networking.tf

Build:

- VPC
- Subnet
- Internet Gateway
- Route Table
- Route Table Association

Explain every AWS resource and every Terraform argument.

---

Stage 7

Create security.tf

Build:

- Security Group
- Ingress Rules
- Egress Rules

Explain:

- stateful security groups
- least privilege
- why 6443 is needed
- production recommendations

---

Stage 8

Create ec2.tf

Create four EC2 instances.

Explain:

- AMI
- instance_type
- subnet_id
- security_groups
- associate_public_ip_address
- private_ip
- tags
- key_name

Explain why every argument exists.

---

Stage 9

Create outputs.tf

Output:

- Public IPs
- Private IPs
- Instance IDs
- VPC ID
- Security Group ID

Explain why outputs are useful.

---

Stage 10

Create terraform.tfvars.example

Explain why production projects separate variables from code.

---

Stage 11

Create README.md

Explain:

- terraform init
- terraform plan
- terraform apply
- terraform destroy

Explain what each command does internally.

---

# Teaching Terraform

Whenever you introduce a new Terraform concept explain:

- Why it exists.
- What problem it solves.
- When professionals use it.
- Common mistakes.
- Best practices.

Topics include:

- Providers
- Resources
- Data Sources
- Variables
- Outputs
- Locals
- State
- Backend
- Dependency Graph
- Expressions
- Interpolation
- Functions
- for_each
- count
- dynamic blocks
- lifecycle
- depends_on
- modules
- remote state
- workspaces
- provisioners
- user_data

Whenever one of these appears in the code, explain it thoroughly.

---

# Best Practices

Teach production-quality Terraform.

Explain topics such as:

- Infrastructure as Code principles
- Idempotency
- Terraform State
- State locking
- Directory organization
- Naming conventions
- Reusable modules
- Variable naming
- Secret management
- Avoiding hardcoded values
- Tagging strategy
- Drift detection
- Importing existing infrastructure
- Formatting with terraform fmt
- Validation
- terraform validate
- terraform plan
- terraform graph
- terraform console
- Linting
- Documentation

Explain not only HOW to do things but WHY professionals do them that way.

---

# Learning Style

Always explain WHY before HOW.

Comment every important Terraform block.

Prefer readability over brevity.

Never assume prior Terraform knowledge.

If multiple approaches exist, explain:

- Which is best for a beginner learning Terraform.
- Which is preferred in production.
- The advantages and disadvantages of each.

Treat this as if you are writing a complete Terraform course while building a real AWS infrastructure that will later be used by Ansible to provision a Kubernetes cluster.