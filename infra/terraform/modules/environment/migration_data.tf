resource "aws_kms_key" "migration" {
  description             = "${local.name} migration data encryption"
  deletion_window_in_days = local.production ? 30 : 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "migration" {
  name          = "alias/${local.name}-migration"
  target_key_id = aws_kms_key.migration.key_id
}

resource "aws_security_group" "database" {
  name        = "${local.name}-aurora"
  description = "PostgreSQL migration target from RDS Proxy only"
  vpc_id      = aws_vpc.this.id

  tags = local.common_tags
}

resource "aws_security_group" "rds_proxy" {
  name        = "${local.name}-rds-proxy"
  description = "PostgreSQL access from EKS workloads"
  vpc_id      = aws_vpc.this.id

  tags = local.common_tags
}

resource "aws_security_group_rule" "proxy_from_cluster" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_proxy.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group_rule" "database_from_proxy" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = aws_security_group.rds_proxy.id
}

resource "aws_security_group_rule" "proxy_to_database" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_proxy.id
  source_security_group_id = aws_security_group.database.id
}

resource "aws_db_subnet_group" "migration" {
  name       = "${local.name}-aurora"
  subnet_ids = values(aws_subnet.private)[*].id

  tags = local.common_tags
}

resource "aws_rds_cluster_parameter_group" "migration" {
  name        = "${local.name}-aurora-postgresql"
  family      = "aurora-postgresql17"
  description = "PostgreSQL settings for the Supabase migration target"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "500"
    apply_method = "immediate"
  }

  tags = local.common_tags
}

resource "aws_rds_cluster" "migration" {
  cluster_identifier              = "${local.name}-migration"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = "17.5"
  database_name                   = "indus"
  master_username                 = "indus_admin"
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = aws_kms_key.migration.arn
  db_subnet_group_name            = aws_db_subnet_group.migration.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.migration.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.migration.arn
  backup_retention_period         = local.production ? 35 : 7
  copy_tags_to_snapshot           = true
  deletion_protection             = local.production
  skip_final_snapshot             = !local.production
  final_snapshot_identifier       = local.production ? "${local.name}-migration-final" : null
  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.database_min_acu
    max_capacity = var.database_max_acu
  }

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "migration" {
  identifier                   = "${local.name}-migration-1"
  cluster_identifier           = aws_rds_cluster.migration.id
  instance_class               = "db.serverless"
  engine                       = aws_rds_cluster.migration.engine
  engine_version               = aws_rds_cluster.migration.engine_version
  auto_minor_version_upgrade   = true
  publicly_accessible          = false
  performance_insights_enabled = true

  tags = local.common_tags
}

data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "${local.name}-rds-proxy"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "rds_proxy" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_rds_cluster.migration.master_user_secret[0].secret_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.migration.arn]
  }
}

resource "aws_iam_role_policy" "rds_proxy" {
  name   = "database-secret"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy.json
}

resource "aws_db_proxy" "migration" {
  name                   = "${local.name}-migration"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = values(aws_subnet.private)[*].id
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_rds_cluster.migration.master_user_secret[0].secret_arn
  }

  tags = local.common_tags
}

resource "aws_db_proxy_default_target_group" "migration" {
  db_proxy_name = aws_db_proxy.migration.name
}

resource "aws_db_proxy_target" "migration" {
  db_cluster_identifier = aws_rds_cluster.migration.id
  db_proxy_name         = aws_db_proxy.migration.name
  target_group_name     = aws_db_proxy_default_target_group.migration.name
}

locals {
  migration_buckets = toset(["artifacts", "audit", "supabase-export"])
}

resource "aws_s3_bucket" "migration" {
  for_each = local.migration_buckets

  bucket        = "${local.name}-${each.value}-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    DataClass = each.value
  })
}

resource "aws_s3_bucket_public_access_block" "migration" {
  for_each = aws_s3_bucket.migration

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "migration" {
  for_each = aws_s3_bucket.migration

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "migration" {
  for_each = aws_s3_bucket.migration

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.migration.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
