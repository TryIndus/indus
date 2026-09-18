locals {
  replacement_secret_names = toset([
    "platform-api",
    "market-data",
    "research-worker",
    "database-migration",
  ])
}

resource "aws_secretsmanager_secret" "replacement" {
  for_each = local.replacement_secret_names

  name                    = "${local.name}/${each.key}"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 7
  tags                    = merge(local.common_tags, { Workload = each.key })
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "Valkey access from EKS workloads"
  vpc_id      = aws_vpc.this.id
  tags        = local.common_tags
}

resource "aws_security_group_rule" "redis_from_cluster" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_elasticache_user" "application" {
  user_id       = "${local.name}-app"
  user_name     = "${local.name}-app"
  access_string = "on ~* +@all"
  engine        = "valkey"

  authentication_mode {
    type = "iam"
  }
  tags = local.common_tags
}

resource "aws_elasticache_user" "disabled_default" {
  user_id       = "${local.name}-default"
  user_name     = "default"
  access_string = "off -@all"
  engine        = "valkey"

  authentication_mode {
    type      = "password"
    passwords = [random_password.disabled_default_redis.result]
  }

  tags = local.common_tags
}

resource "random_password" "disabled_default_redis" {
  length  = 40
  special = false
}

resource "aws_elasticache_user_group" "application" {
  user_group_id = "${local.name}-app"
  engine        = "valkey"
  user_ids      = [aws_elasticache_user.disabled_default.user_id, aws_elasticache_user.application.user_id]
  tags          = local.common_tags
}

resource "aws_elasticache_serverless_cache" "application" {
  name                     = local.name
  description              = "${local.name} Sidekiq and application cache"
  engine                   = "valkey"
  major_engine_version     = "8"
  kms_key_id               = aws_kms_key.data.arn
  subnet_ids               = values(aws_subnet.private)[*].id
  security_group_ids       = [aws_security_group.redis.id]
  user_group_id            = aws_elasticache_user_group.application.user_group_id
  snapshot_retention_limit = local.production ? 7 : 1

  cache_usage_limits {
    data_storage {
      maximum = local.production ? 20 : 5
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = local.production ? 10000 : 5000
    }
  }

  tags = local.common_tags
}

resource "aws_security_group" "kafka" {
  name        = "${local.name}-kafka"
  description = "MSK IAM access from EKS workloads"
  vpc_id      = aws_vpc.this.id
  tags        = local.common_tags
}

resource "aws_security_group_rule" "kafka_from_cluster" {
  type                     = "ingress"
  from_port                = 9098
  to_port                  = 9098
  protocol                 = "tcp"
  security_group_id        = aws_security_group.kafka.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_msk_serverless_cluster" "events" {
  cluster_name = local.name

  vpc_config {
    subnet_ids         = values(aws_subnet.private)[*].id
    security_group_ids = [aws_security_group.kafka.id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = local.common_tags
}
