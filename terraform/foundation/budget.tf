# One monthly budget, one email each time spend crosses a level in var.alert_levels_usd.
# (One budget with many alerts is free; separate budgets beyond the first 2 are paid.)
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(max(var.alert_levels_usd...))
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset(var.alert_levels_usd)
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
