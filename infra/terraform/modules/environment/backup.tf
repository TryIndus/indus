resource "aws_backup_vault" "primary" {
  name        = local.name
  kms_key_arn = aws_kms_key.data.arn
  tags        = local.common_tags
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "backup" {
  name               = "${local.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "primary" {
  name = local.name

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 7 * * ? *)"

    lifecycle {
      delete_after = local.production ? 365 : 30
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "primary" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${local.name}-aurora"
  plan_id      = aws_backup_plan.primary.id
  resources    = [aws_rds_cluster.data.arn]

  depends_on = [aws_iam_role_policy_attachment.backup]
}
