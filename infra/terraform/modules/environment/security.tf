resource "aws_secretsmanager_secret" "legacy_next" {
  name                    = var.legacy_next_secret_name
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "application" {
  count             = var.enable_supplementary_monitoring ? 1 : 0
  name              = "/indus/${var.environment}/legacy-next"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_sns_topic" "alerts" {
  count             = var.enable_supplementary_monitoring ? 1 : 0
  name              = "${local.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts" {
  for_each = var.enable_supplementary_monitoring ? var.alert_email_addresses : toset([])

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}
