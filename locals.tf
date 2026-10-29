# =============================================================================
# FILE:        locals.tf
# PURPOSE:     Define computed local values used throughout the project.
#              Locals are DRY helpers — compute once, reference many times.
# LOADED:      At plan time, evaluated lazily when first referenced.
# OPTIONAL:    Yes, but omitting them leads to duplicated expressions
#              that are harder to maintain and error-prone.
# DEPENDS ON:  variables.tf (locals often reference variables)
# =============================================================================

# -----------------------------------------------------------------------------
# locals {} — a block that defines named values computed from other values.
#
# locals are NOT variables:
#   - Variables:  provide INPUT to the configuration (external)
#   - Locals:     compute values INTERNAL to the configuration
#   - Outputs:    expose values AFTER the configuration runs (output)
#
# Think of locals as "let bindings" in functional programming —
# assign a name to an expression so you only write it once.
#
# Common use cases for locals:
#   ✅ Constructing names from multiple variables (tag merging)
#   ✅ Formatting strings for common patterns
#   ✅ Pre-computing complex expressions used in many resources
#   ✅ Mapping between different naming conventions
#   ❌ Storing secrets (use variables with sensitive=true instead)
#   ❌ Duplicating what should be a variable
#   ❌ Over-complicating simple expressions
# -----------------------------------------------------------------------------
locals {

  # ---------------------------------------------------------------------------
  # NAMING CONVENTION: <prefix>-<name>
  #
  # Why compute names? Because consistent naming is critical for:
  #   - AWS Console searchability (find all k8s-lab resources)
  #   - Cost allocation (filter billing by resource name prefix)
  #   - Avoiding collisions (if you run multiple labs in same account)
  #
  # Best practice: Always include a project prefix and environment
  # in resource names. This makes multi-environment accounts manageable.
  # ---------------------------------------------------------------------------
  name_prefix = "k8s-lab"

  # ---------------------------------------------------------------------------
  # COMMON TAGS — merged with provider-level default_tags for resources
  # that need additional tags beyond the global ones.
  #
  # Provider default_tags (from provider.tf) are applied automatically.
  # These locals are for tags that vary between resources (like Name).
  # ---------------------------------------------------------------------------
  common_tags = {
    Project     = "k8s-lab"
    ManagedBy   = "Terraform"
    Environment = "lab"
  }

  # ---------------------------------------------------------------------------
  # INSTANCE CONFIGURATION MAP
  #
  # Instead of writing four nearly-identical resource blocks, we define
  # the unique data per instance in a local map, then loop over it with
  # `for_each` in ec2.tf.
  #
  # Benefits:
  #   1. Single source of truth for instance definitions
  #   2. Adding a 5th instance = one line in this map (no copy-paste!)
  #   3. Impossible to accidentally configure instances differently
  #   4. Easy to read — all instance data in one place
  #
  # Note: Each key becomes the Terraform resource address:
  #   aws_instance.managed["control-plane-01"]
  #   aws_instance.managed["worker-01"]
  #   This makes terraform state and plan output much more readable.
  # ---------------------------------------------------------------------------
  instances = {
    "ansible-controller" = {
      private_ip = "10.1.0.7"
      role       = "ansible-controller"
      # This server runs Ansible, not Kubernetes.
      # It needs SSH access to all other instances.
    }
    "control-plane-01" = {
      private_ip = "10.1.0.10"
      role       = "control-plane"
      # This is the Kubernetes control plane node.
      # It runs: kube-apiserver, etcd, controller-manager, scheduler.
    }
    "worker-01" = {
      private_ip = "10.1.0.6"
      role       = "worker"
      # Worker nodes run user workloads (pods).
    }
    "worker-02" = {
      private_ip = "10.1.0.8"
      role       = "worker"
      # Second worker for HA demonstrations and load distribution.
    }
  }
# ---------------------------------------------------------------------------
  # MANAGED INSTANCES — K8s nodes only (excludes ansible-controller)
  #
  # We filter the full instances map to get ONLY the 3 nodes that Ansible
  # will manage: control-plane-01, worker-01, worker-02.
  #
  # These must be created and bootstrapped BEFORE the ansible-controller
  # instance is created. This filtered map lets us create them from a
  # dedicated aws_instance.managed resource block.
  # ---------------------------------------------------------------------------
  managed_instances = {
    for name, config in local.instances : name => config
    if config.role != "ansible-controller"
  }
  # ---------------------------------------------------------------------------
  # Why a map instead of count with a list?
  #
  #   count approach:
  #     resource "aws_instance" "this" { count = 4 ... }
  #     Problem: instances are indexed as this[0], this[1], this[2], this[3]
  #     Adding/removing an instance in the MIDDLE shifts indices and
  #     Terraform will DESTROY and RECREATE instances unnecessarily.
  #
  #   for_each with map approach (OUR CHOICE):
  #     resource "aws_instance" "this" { for_each = local.instances ... }
  #     Instances are indexed by name: this["ansible-controller"]
  #     Adding/removing only affects the changed entry, NOT the others.
  #
  #   This is the #1 most common Terraform mistake.
  #   for_each > count in 95% of cases.
  # ---------------------------------------------------------------------------
}