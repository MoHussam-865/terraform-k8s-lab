# Terraform Kubernetes Lab — AWS Infrastructure

A production-quality Terraform project that provisions the AWS infrastructure for a hands-on Kubernetes lab. Built with detailed educational comments — designed to **teach** Terraform while building real infrastructure.

## Architecture

```
Internet
    ↓
Internet Gateway
    ↓
Route Table (0.0.0.0/0 → IGW)
    ↓
VPC (10.1.0.0/24)
    ↓
Public Subnet (10.1.0.0/28)
    ↓
Security Group (SSH:22 + K8s API:6443)
    ↓
┌─────────────────────┬──────────────────┬──────────────┬──────────────┐
│ ansible-controller  │ control-plane-01 │  worker-01   │  worker-02   │
│    10.1.0.7         │    10.1.0.10     │  10.1.0.6    │  10.1.0.8    │
│  (Ansible mgmt)     │  (K8s control)   │ (K8s worker) │ (K8s worker) │
└─────────────────────┴──────────────────┴──────────────┴──────────────┘
```

All instances: Ubuntu 22.04 LTS, t3.small, 20 GiB encrypted gp3 EBS.

## Prerequisites

1. **AWS Account** with programmatic access (Access Key + Secret Key)
2. **AWS CLI** installed and configured (`aws configure`)
3. **Terraform** >= 1.5.0 installed
4. **EC2 Key Pair** created in your AWS account (us-east-1 region)
5. **SSH client** for connecting to instances

## Quick Start

```bash
# 1. Clone and enter the project
cd terraform-k8s-lab

# 2. Create your variable definitions file
cp terraform.tfvars.example terraform.tfvars

# 3. EDIT terraform.tfvars — set your key_name!
#    key_name = "your-actual-key-pair-name"

# 4. Initialize Terraform (downloads providers, sets up state)
terraform init

# 5. Preview what will be created (NO changes made yet)
terraform plan

# 6. Create the infrastructure
terraform apply

# 7. Generate Ansible inventory
terraform output -raw ansible_inventory > hosts.ini

# 8. SSH into the ansible controller:
ssh -i ~/.ssh/your-key.pem ubuntu@<public-ip-from-output>

# 9. When you're done, destroy everything
terraform destroy
```

## Terraform Commands Explained

| Command | What It Does | When To Use |
|---|---|---|
| `terraform init` | Downloads providers, initializes backend, sets up `.terraform/` | After cloning, after adding providers |
| `terraform plan` | Compares desired vs actual state, shows diff | Before every apply |
| `terraform apply` | Creates/updates resources to match desired state | After reviewing plan |
| `terraform destroy` | Destroys ALL resources. Irreversible. | When lab is done |
| `terraform validate` | Checks syntax and consistency (no remote calls) | After editing .tf files |
| `terraform fmt` | Rewrites files to canonical format | Before committing |
| `terraform output` | Shows outputs. `-json` for machine, `-raw` for pipes | After apply |
| `terraform show` | Displays current state | Debugging |
| `terraform state list` | Lists all managed resources | Understanding scope |
| `terraform graph` | DOT graph of dependencies (pipe to `dot -Tsvg`) | Visualizing
### What happens during `terraform init`?

1. Reads `versions.tf` — checks Terraform binary version
2. Downloads provider plugins to `.terraform/providers/`
3. Creates `.terraform.lock.hcl` — pins exact provider versions
4. Initializes the backend (local by default)

### What happens during `terraform plan`?

1. Reads all `.tf` files and loads variable values
2. Refreshes state by querying AWS for current status
3. Builds a dependency graph from resource references
4. Compares desired vs. actual state, prints diff (`+`/-/`~`/`-/+`)

### What happens during `terraform apply`?

1. Runs plan, then walks dependency graph in parallel
2. Makes AWS API calls in correct order (VPC → Subnet → SG → EC2)
3. Stores results in `terraform.tfstate`, prints outputs

## File Structure

| File | Purpose | Loaded |
|---|---|---|
| `versions.tf` | Pin Terraform & provider versions | `init` |
| `provider.tf` | AWS provider (region, auth, tags) | `init` |
| `variables.tf` | Input variables with validation | Plan/apply |
| `locals.tf` | Computed local values | Plan/apply |
| `networking.tf` | VPC, Subnet, IGW, Route Table | Plan/apply |
| `security.tf` | Security Groups and rules | Plan/apply |
| `ec2.tf` | EC2 instances (AMI lookup + 4 servers) | Plan/apply |
| `outputs.tf` | Output values (IPs, IDs, inventory) | After apply |
| `terraform.tfvars.example` | Variable template (committed) | Never |
| `.gitignore` | Files excluded from Git | `git add` |

## Security Notes

- **SSH open to 0.0.0.0/0**: Acceptable for short-lived lab. Production: restrict to your IP or use SSM.
- **K8s API open to 0.0.0.0/0**: Acceptable for lab. Production: VPN or known CIDRs.
- **Credentials**: Never hardcoded. Uses AWS credential chain.
- **State file**: Don't commit `terraform.tfstate`.

## Cost Estimate

| Resource | Qty | Rate | Monthly |
|---|---|---|---|
| t3.small EC2 | 4 | $0.0208/hr | ~$60.80 |
| 20 GiB gp3 EBS | 4x20GB | $0.08/GB-month | ~$6.40 |
| Internet egress | Variable | $0.09/GB | ~$2-5 |
| **Total** | | | **~$70/month** |

**Destroy when not in use**: `terraform destroy`

## Troubleshooting

| Problem | Fix |
|---|---|
| No credentials | `aws configure` or set AWS_ACCESS_KEY_ID |
| Key pair missing | Create key pair in us-east-1 |
| t3.small denied | Request limit increase or try t3.micro |
| No internet on instances | Check route: 0.0.0.0/0 → IGW |
| Plan shows AMI change | Expected — lifecycle.ignore_changes handles it |