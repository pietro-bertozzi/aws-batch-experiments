variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "name" {
  description = "Prefix for every resource we create."
  type        = string
  default     = "exp"
}

variable "budget_email" {
  description = "Where AWS Budgets sends cost alerts. Set in terraform.tfvars (not committed)."
  type        = string
}

variable "alert_levels_usd" {
  description = "Email me when this month's spend crosses each of these amounts (USD). Max 10 levels."
  type        = list(number)
  default     = [1, 2, 5, 10, 20, 50, 100, 200]
}

variable "results_expire_days" {
  description = "Delete results/checkpoints after this many days."
  type        = number
  default     = 90
}
