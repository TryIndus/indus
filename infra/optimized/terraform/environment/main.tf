provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]
  default_tags { tags = merge(var.tags, { Project = "indus", Profile = "optimized", Environment = "production", ManagedBy = "Terraform", Repository = var.github_repository }) }
}

data "aws_availability_zones" "available" { state = "available" }
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_ssm_parameter" "al2023" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }

locals {
  name        = "indus-optimized"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  common_tags = { Profile = "optimized", Topology = "single-host-single-az" }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = local.name })
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${local.name}-igw" })
}
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[0]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
  map_public_ip_on_launch = false
  tags                    = merge(local.common_tags, { Name = "${local.name}-${local.azs[0]}-public" })
}
resource "aws_subnet" "database" {
  for_each          = toset(local.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, 4 + index(local.azs, each.key))
  tags              = merge(local.common_tags, { Name = "${local.name}-${each.key}-database" })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.common_tags, { Name = "${local.name}-public" })
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${local.name}-database-isolated" })
}
resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}

resource "aws_security_group" "host" {
  name   = "${local.name}-host"
  vpc_id = aws_vpc.this.id
  ingress {
    description = "ACME HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Product HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags
}
resource "aws_security_group" "database" {
  name   = "${local.name}-database"
  vpc_id = aws_vpc.this.id
  tags   = local.common_tags
}
resource "aws_security_group_rule" "database_from_host" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = aws_security_group.host.id
}
resource "aws_eip" "host" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name}-host" })
}

data "aws_iam_policy_document" "host_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "host" {
  name               = "${local.name}-host"
  assume_role_policy = data.aws_iam_policy_document.host_assume.json
  tags               = local.common_tags
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "host" {
  name = "${local.name}-host"
  role = aws_iam_role.host.name
}
resource "aws_kms_key" "data" {
  description             = "Indus optimized data encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.common_tags
}
resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
resource "aws_secretsmanager_secret" "runtime" {
  for_each                = toset(["platform-api", "market-data", "research-worker"])
  name                    = "${local.name}/${each.key}"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 7
  tags                    = local.common_tags
}
resource "aws_iam_role_policy" "host_runtime" {
  name   = "runtime-secrets-and-artifacts"
  role   = aws_iam_role.host.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [for secret in aws_secretsmanager_secret.runtime : secret.arn] }, { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.data.arn] }] })
}
resource "aws_iam_role_policy" "host_ecr" {
  name   = "pull-optimized-images"
  role   = aws_iam_role.host.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = values(var.ecr_repository_arns) }] })
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-database"
  subnet_ids = values(aws_subnet.database)[*].id
  tags       = local.common_tags
}
resource "aws_db_parameter_group" "this" {
  name   = "${local.name}-postgres17"
  family = "postgres17"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  tags = local.common_tags
}
resource "aws_db_instance" "this" {
  identifier                    = local.name
  engine                        = "postgres"
  engine_version                = "17"
  instance_class                = var.database_instance_class
  allocated_storage             = var.database_allocated_storage_gib
  storage_type                  = "gp3"
  storage_encrypted             = true
  kms_key_id                    = aws_kms_key.data.arn
  db_name                       = "indus"
  username                      = "indus_admin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.data.arn
  db_subnet_group_name          = aws_db_subnet_group.this.name
  vpc_security_group_ids        = [aws_security_group.database.id]
  parameter_group_name          = aws_db_parameter_group.this.name
  availability_zone             = local.azs[0]
  multi_az                      = false
  publicly_accessible           = false
  backup_retention_period       = var.database_backup_retention_days
  deletion_protection           = true
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${local.name}-final"
  auto_minor_version_upgrade    = true
  performance_insights_enabled  = true
  tags                          = local.common_tags
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name}-artifacts-${var.account_id}"
  tags   = local.common_tags
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.data.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
resource "aws_iam_role_policy" "host_artifacts" {
  name   = "report-artifacts"
  role   = aws_iam_role.host.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"], Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"] }] })
}

resource "aws_cognito_user_pool" "this" {
  name                     = local.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"
  mfa_configuration        = "OFF"
  dynamic "email_configuration" {
    for_each = var.enable_branded_cognito_email ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = "Indus <notifications@${var.preview_domain_name}>"
      source_arn            = aws_ses_domain_identity.cognito[0].arn
    }
  }
  dynamic "verification_message_template" {
    for_each = var.enable_branded_cognito_email ? [1] : []
    content {
      default_email_option = "CONFIRM_WITH_CODE"
      email_subject        = "Your Indus verification code"
      email_message        = "Use code {####} to verify your email. Return to https://${var.preview_domain_name}/auth to continue."
    }
  }
  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 3
  }
  tags       = local.common_tags
  depends_on = [aws_ses_domain_identity_verification.cognito, aws_route53_record.cognito_dkim]
}
resource "aws_ses_domain_identity" "cognito" {
  count  = var.enable_branded_cognito_email ? 1 : 0
  domain = var.preview_domain_name
}
resource "aws_route53_record" "cognito_ses_verification" {
  count   = var.enable_branded_cognito_email ? 1 : 0
  zone_id = aws_route53_zone.preview.zone_id
  name    = "_amazonses.${var.preview_domain_name}"
  type    = "TXT"
  ttl     = 300
  records = [aws_ses_domain_identity.cognito[0].verification_token]
}
resource "aws_ses_domain_identity_verification" "cognito" {
  count      = var.enable_branded_cognito_email ? 1 : 0
  domain     = aws_ses_domain_identity.cognito[0].domain
  depends_on = [aws_route53_record.cognito_ses_verification]
}
resource "aws_ses_domain_dkim" "cognito" {
  count  = var.enable_branded_cognito_email ? 1 : 0
  domain = aws_ses_domain_identity.cognito[0].domain
}
resource "aws_route53_record" "cognito_dkim" {
  count   = var.enable_branded_cognito_email ? 3 : 0
  zone_id = aws_route53_zone.preview.zone_id
  name    = "${aws_ses_domain_dkim.cognito[0].dkim_tokens[count.index]}._domainkey.${var.preview_domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_ses_domain_dkim.cognito[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}
resource "aws_cognito_user_pool_client" "web" {
  name                                 = "web"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls
  access_token_validity                = 60
  id_token_validity                    = 60
  refresh_token_validity               = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_instance" "host" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.host.id]
  iam_instance_profile        = aws_iam_instance_profile.host.name
  associate_public_ip_address = false
  user_data                   = file("${path.module}/../../runtime/bootstrap.sh")
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    encrypted             = true
    kms_key_id            = aws_kms_key.data.arn
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    delete_on_termination = false
  }
  tags = merge(local.common_tags, { Name = "${local.name}-host" })
}
resource "aws_eip_association" "host" {
  allocation_id = aws_eip.host.id
  instance_id   = aws_instance.host.id
}
resource "aws_route53_record" "preview" {
  zone_id = aws_route53_zone.preview.zone_id
  name    = "@"
  type    = "A"
  ttl     = 300
  records = [aws_eip.host.public_ip]
}
resource "aws_route53_zone" "preview" {
  name = var.preview_domain_name
  tags = merge(local.common_tags, { Name = "${local.name}-preview-zone" })
}
resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}
resource "aws_sns_topic_subscription" "alerts" {
  for_each  = var.alert_email_addresses
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${local.name}-database-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 80
  evaluation_periods  = 3
  period              = 300
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  tags                = local.common_tags
}
resource "aws_cloudwatch_metric_alarm" "host_status" {
  alarm_name          = "${local.name}-host-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 2
  period              = 60
  statistic           = "Maximum"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.host.id }
  tags                = local.common_tags
}
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "FORECASTED"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
  tags = local.common_tags
}
