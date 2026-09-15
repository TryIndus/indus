resource "aws_backup_vault" "migration" {
  name        = "${local.name}-migration"
  kms_key_arn = aws_kms_key.migration.arn
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

resource "aws_iam_role" "migration_backup" {
  name               = "${local.name}-migration-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "migration_backup" {
  role       = aws_iam_role.migration_backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "migration" {
  name = "${local.name}-migration"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.migration.name
    schedule          = "cron(0 7 * * ? *)"

    lifecycle {
      delete_after = local.production ? 365 : 30
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "migration" {
  iam_role_arn = aws_iam_role.migration_backup.arn
  name         = "${local.name}-aurora"
  plan_id      = aws_backup_plan.migration.id
  resources    = [aws_rds_cluster.migration.arn]

  depends_on = [aws_iam_role_policy_attachment.migration_backup]
}
