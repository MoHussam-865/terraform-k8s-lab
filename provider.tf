# =============================================================================
# FILE:        provider.tf
# PURPOSE:     Configure HOW Terraform connects to AWS (region, auth, defaults).
# LOADED:      After version checks pass during `terraform init`.
# OPTIONAL:    No. Without a provider block, Terraform has no API to talk to.
# DEPENDS ON:  versions.tf (provider must match a required_providers entry)
# =============================================================================

# -----------------------------------------------------------------------------
# provider "aws" — the AWS provider configuration block.
#
# A provider is a plugin that translates Terraform's declarative language
# into API calls for a specific cloud or service. The AWS provider wraps
# the AWS SDK for Go and exposes ~1000+ resources (EC2, VPC, IAM, S3, ...).
#
# You can have MULTIPLE provider blocks for the same provider:
#   - One for us-east-1 (production)
#   - One for eu-west-1 (disaster recovery)
#   Each is differentiated by an `alias` argument.
# -----------------------------------------------------------------------------
provider "aws" {

  # ---------------------------------------------------------------------------
  # region — the AWS region where ALL resources will be created.
  #
  # Why us-east-1 for a lab?
  #   - Lowest AWS pricing for most services
  #   - All instance types (t3.small) are available
  #   - No AZ capacity issues that can happen in smaller regions
  #
  # Production note: In real projects, the region should be a VARIABLE,
  # not hardcoded. This lets you deploy to different regions for DR or
  # regional compliance. We use a variable for this later.
  #
  # DEFAULT REGION CHAIN (in order of priority):
  #   1. The `region` argument in this provider block (HIGHEST priority)
  #   2. AWS_DEFAULT_REGION environment variable
  #   3. AWS_REGION environment variable
  #   4. region in ~/.aws/config (for the active profile)
  #   5. Falls back to us-east-1 if nothing else is set
  #
  # For learning, we hardcode us-east-1. In production, use a variable.
  # ---------------------------------------------------------------------------
  region = "us-east-1"

  # ---------------------------------------------------------------------------
  # CREDENTIALS — NOT hardcoded here!
  #
  # Terraform uses the standard AWS SDK credential chain:
  #
  #   Priority 1: Environment variables
  #     - AWS_ACCESS_KEY_ID
  #     - AWS_SECRET_ACCESS_KEY
  #     - AWS_SESSION_TOKEN (if using temporary creds)
  #
  #   Priority 2: Shared credentials file (~/.aws/credentials)
  #     - Uses the [default] profile unless AWS_PROFILE is set
  #     - For production: use named profiles and AWS_PROFILE env var
  #
  #   Priority 3: IAM Role (EC2 instance profile, ECS task role)
  #     - BEST practice for CI/CD pipelines running on AWS
  #     - Zero hardcoded credentials — AWS STS handles everything
  #
  #   Priority 4: Web Identity Token (OIDC — e.g., GitHub Actions)
  #     - Modern CI/CD approach — no long-lived credentials at all
  #
  # WHAT NOT TO DO:
  #   ❌ access_key = "AKIA..."    (secret in code = leaked on git push)
  #   ❌ secret_key = "wJalrX..."  (same problem)
  #   ❌ token = "..."              (temporary, but still a leak vector)
  #
  # The ONLY exception: local learning labs where you export env vars
  # before running terraform. Even then, NEVER commit them to git.
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # default_tags — tags automatically applied to EVERY resource this
  # provider creates.
  #
  # Introduced in AWS provider v4.6+ and improved in 5.x. This is a
  # MASSIVE time-saver and consistency enforcer.
  #
  # Without default_tags: You would manually add tags to every single
  # resource block. For 4 EC2 instances + VPC + Subnet + IGW + RT +
  # SG + Route Association = ~10 resources. Each needs the same tags.
  # That's ~10 places where you can make a typo like "Enviroment".
  #
  # With default_tags: Define once, applied everywhere automatically.
  #
  # Tags defined directly on a resource OVERRIDE default_tags for that
  # specific key. This gives you per-resource flexibility when needed.
  #
  # Tags on ASGs and launch templates: default_tags also propagate
  # to EC2 instances launched by Auto Scaling Groups. This is critical
  # for cost allocation in production environments.
  # ---------------------------------------------------------------------------
  default_tags {
    tags = {
      Project     = "k8s-lab"
      ManagedBy   = "Terraform"
      Purpose     = "Kubernetes learning lab"
      Environment = "lab"
      Owner       = "student" # 🔴 CHANGE THIS to your name/email
    }
  }
}