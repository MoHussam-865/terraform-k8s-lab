# =============================================================================
# FILE:        networking.tf
# PURPOSE:     Provision all AWS networking resources for the K8s lab.
#              Builds the foundational layer: VPC → Subnet → IGW → Routing.
# LOADED:      At plan time. Resources are evaluated and dependency graph
#              is computed BEFORE any API calls are made.
# OPTIONAL:    No. Without networking, EC2 instances have nowhere to live.
# DEPENDS ON:  variables.tf, locals.tf
#
# RESOURCES CREATED (in dependency order):
#   1. aws_vpc                      — The isolated virtual network
#   2. aws_subnet                   — A CIDR range inside the VPC
#   3. aws_internet_gateway         — Allows traffic VPC ↔ internet
#   4. aws_route_table              — Rules for directing traffic
#   5. aws_route                    — A specific route (0.0.0.0/0 → IGW)
#   6. aws_route_table_association  — Connects subnet to route table
#
# DATA SOURCES USED:
#   - aws_availability_zones: Dynamically fetches available AZs
# =============================================================================

# =============================================================================
# 1. VPC — Virtual Private Cloud
#
# A VPC is your isolated section of AWS. Think of it as a private data
# center. Every AWS account has a "default VPC" but professionals ALWAYS
# create custom VPCs for projects. The default VPC is not configurable
# enough and mixing projects in one VPC creates chaos.
# =============================================================================
resource "aws_vpc" "main" {

  # CIDR block: 10.1.0.0/24 = 256 addresses. CANNOT be changed after creation
  # (would require destroy + recreate of the entire VPC).
  cidr_block = var.vpc_cidr

  # enable_dns_hostnames: Assigns public DNS names to instances with
  # public IPs. Needed so we can identify instances by hostname.
  # Also enables DNS resolution via the VPC DNS server at base+2.
  #
  # NOTE: DNS resolution (VPC base+2 resolver) is always available;
  # enable_dns_hostnames controls whether instances get public DNS names.
  # The deprecated `enable_dns_support` attribute does not exist in the
  # Terraform AWS provider — `enable_dns_hostnames` is the correct attribute.
  enable_dns_hostnames = true

  # Tags: "Name" tag appears in the AWS Console. Without it, you see
  # anonymous IDs like "vpc-0a1b2c...". ALWAYS set a Name tag.
  # Project/ManagedBy/etc come from provider default_tags in provider.tf.
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# =============================================================================
# DATA SOURCE: AWS Availability Zones
#
# A data source is READ-ONLY: it fetches information from AWS without
# creating or modifying anything. Data sources run at plan time, BEFORE
# resources. They let you reference dynamic values instead of hardcoding
# strings like "us-east-1a" that differ between accounts.
# =============================================================================
data "aws_availability_zones" "available" {
  # Only AZs that are fully operational
  state = "available"

  # Exclude Local Zones and Wavelength Zones (only standard AZs)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# =============================================================================
# 2. SUBNET — A range of IP addresses within the VPC
#
# Resources (EC2, RDS, etc.) are launched INTO a subnet. Every subnet
# lives in exactly ONE Availability Zone.
#
# PUBLIC subnet: has a route to Internet Gateway → internet access both ways.
# PRIVATE subnet: no route to IGW → needs NAT Gateway for outbound only.
# Our subnet is PUBLIC because we need to SSH directly into instances.
# =============================================================================
resource "aws_subnet" "public" {

  # vpc_id references aws_vpc.main.id — this creates an IMPLICIT dependency.
  # Terraform sees this reference and knows: create VPC first, then subnet.
  # Always prefer implicit deps over explicit `depends_on`.
  vpc_id = aws_vpc.main.id

  # CIDR block must be a subset of the VPC CIDR. Terraform validates this
  # at plan time. 10.1.0.0/28 is inside 10.1.0.0/24 ✓
  cidr_block = var.subnet_cidr

  # Dynamically pick the first available AZ. element(list, 0) returns the
  # first item. AZ names are randomized per account — never hardcode them.
  availability_zone = element(data.aws_availability_zones.available.names, 0)

  # Automatically assign a public IPv4 to instances launched in this subnet.
  # True = simpler config. Production might set false for explicit control.
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet"
  }
}

# =============================================================================
# 3. INTERNET GATEWAY — The bridge between VPC and the public internet
# =============================================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# =============================================================================
# 4. ROUTE TABLE — A set of rules that determines where network traffic goes
# =============================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

# =============================================================================
# 5. ROUTE — A single entry in the route table
#
# This specific route says: "Any traffic destined for the entire internet
# (0.0.0.0/0) should be sent to the Internet Gateway."
#
# Without this route, even with an IGW attached to the VPC, instances
# cannot reach the internet because there's no ROUTE telling traffic
# to go through the IGW.
#
# 0.0.0.0/0 means "any IPv4 address" — it's the default route (catch-all).
# It matches EVERYTHING that doesn't have a more specific route.
# =============================================================================
resource "aws_route" "internet_access" {
  # Which route table to add this route to
  route_table_id = aws_route_table.public.id

  # destination_cidr_block: where is the traffic going?
  # 0.0.0.0/0 = all non-local traffic → the default internet route
  destination_cidr_block = "0.0.0.0/0"

  # gateway_id: where to send matching traffic
  # aws_internet_gateway.main.id tells Terraform the route depends on the IGW
  gateway_id = aws_internet_gateway.main.id

  # NOTE: We don't set tags on aws_route because routes don't support tags
  # in AWS (they're always part of a route table and inherit context).
}

# =============================================================================
# 6. ROUTE TABLE ASSOCIATION — Links a subnet to a route table
#
# Every subnet MUST be associated with exactly ONE route table. If you
# don't explicitly associate a subnet, it uses the VPC's MAIN route table.
#
# By creating an explicit association, we guarantee our public subnet
# uses OUR route table (with the IGW route), not the default main table
# (which only has the local route).
#
# This is the final step that makes the subnet truly "public":
#   VPC ✅ → Subnet ✅ → IGW ✅ → Route Table ✅ → Route ✅ → ASSOCIATION ✅
# =============================================================================
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# NETWORKING LAYER COMPLETE!
#
# Here's what Terraform's dependency graph looks like for this layer:
#
#   data.aws_availability_zones.available (fetches AZ list)
#                ↓
#   aws_vpc.main (creates the VPC)
#       ↓                    ↓
#   aws_subnet.public    aws_internet_gateway.main
#       ↓                    ↓
#       └──→ aws_route_table.public
#                ↓
#            aws_route.internet_access
#                ↓
#            aws_route_table_association.public
#
# This graph is computed AUTOMATICALLY by Terraform from attribute
# references. You don't write it — you write references and Terraform
# derives the graph. This is the magic of declarative IaC.
# =============================================================================