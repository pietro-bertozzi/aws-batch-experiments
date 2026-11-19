variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "name" {
  description = "Prefix for every resource we create (must match foundation)."
  type        = string
  default     = "exp"
}

# One entry per compute environment + queue. Delete an entry and apply to remove
# it. To add a GPU later, add an entry (e.g. instance_types = ["g5"]).
variable "compute_environments" {
  description = "Map of name => settings. Each gets its own compute environment and job queue."
  type = map(object({
    spot           = bool
    max_vcpus      = number
    instance_types = list(string)
  }))
  default = {
    spot = {
      spot           = true
      max_vcpus      = 32                       # = current Spot quota in eu-north-1
      instance_types = ["c7i-flex", "m7i-flex"] # free plan only allows free-tier-eligible types
    }
    ondemand = {
      spot           = false
      max_vcpus      = 16 # = current on-demand quota in eu-north-1
      instance_types = ["c7i-flex", "m7i-flex"]
    }
  }
}
