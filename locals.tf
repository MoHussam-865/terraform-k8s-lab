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
    Project = "k8s-lab"
    ManagedBy = "Terraform"
    Environment = "lab"
  }

  # ---------------------------------------------------------------------------
  # INVENTORY GROUPS — Used later for Ansible hosts file generation.
  # These group labels map to the sections in the generated hosts file.
  # ---------------------------------------------------------------------------
  inventory_groups = {
    haproxy = "haproxy"
    masters = "masters"
    workers = "workers"
    prometheus = "prometheus"
  }
}