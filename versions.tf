# =============================================================================
# FILE:        versions.tf
# PURPOSE:     Pin Terraform and provider versions to guarantee reproducible
#              infrastructure across every team member and CI/CD pipeline.
# LOADED:      By `terraform init` — runs before anything else.
# OPTIONAL:    Technically yes, but omitting it is a production anti-pattern.
# =============================================================================

# -------------------------------------------------------------------
# terraform {} — the top-level block that configures Terraform itself.
# This is NOT a resource, data source, or variable. It controls the
# behavior of the Terraform binary.
# -------------------------------------------------------------------
terraform {

  # -----------------------------------------------------------------
  # required_version
  # Constrains which versions of the `terraform` CLI binary are
  # allowed to run this configuration.
  #
  # Syntax: ">= 1.5.0, < 2.0.0"
  #   - ">= 1.5.0" : At least version 1.5.0 (we use features from it)
  #   - "< 2.0.0"  : Reject 2.x (it doesn't exist yet, but when it
  #                   does, it WILL have breaking changes)
  #
  # Why pin? Terraform 1.x introduced `count`, `for_each`, and
  # `depends_on` that work differently from 0.x. If someone runs
  # `terraform apply` with 0.14, it WILL break. This constraint
  # blocks them with a clear error message.
  #
  # Common mistake: only specifying ">= 1.0". This allows 3.0 in
  # the future, which WILL break. Always use an upper bound.
  # -----------------------------------------------------------------
  required_version = ">= 1.5.0, < 2.0.0"

  # -----------------------------------------------------------------
  # required_providers
  # Declares which providers (plugins) this project needs.
  #
  # Providers are Terraform's way of talking to APIs:
  #   - AWS provider    → talks to AWS APIs (EC2, VPC, IAM, etc.)
  #   - Kubernetes provider → talks to the K8s API server
  #   - Random provider → generates random values (for testing)
  #
  # Each provider is versioned independently from Terraform.
  # -----------------------------------------------------------------
  required_providers {

    # ---------------------------------------------------------------
    # aws — the HashiCorp-maintained provider for Amazon Web Services
    #
    # source: The fully-qualified provider address.
    #   Format: "namespace/provider_name"
    #   - "hashicorp/aws" means: published by HashiCorp, named "aws"
    #
    # version: SemVer constraint like required_version above.
    #   ">= 5.30, < 6.0" means:
    #   - At least 5.30 (has t3.small, newer AMI filter syntax)
    #   - But not 6.x (unknown breaking changes)
    #
    # Why 5.x? The AWS provider 5.x introduced significant
    # improvements to default_tags and S3 handling. 4.x is still
    # widely used but 5.x is the current major version as of 2024.
    # ---------------------------------------------------------------
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30, < 6.0"
    }
  }
}