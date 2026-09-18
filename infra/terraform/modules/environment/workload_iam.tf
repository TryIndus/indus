data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = local.common_tags
}

locals {
  workload_service_accounts = {
    legacy-next = {
      namespace = "indus"
      name      = "indus-legacy-next"
    }
    aws-load-balancer-controller = {
      namespace = "kube-system"
      name      = "aws-load-balancer-controller"
    }
    platform-api      = { namespace = "indus", name = "platform-api" }
    sidekiq           = { namespace = "indus", name = "sidekiq" }
    platform-outbox   = { namespace = "indus", name = "platform-outbox" }
    reports-consumer  = { namespace = "indus", name = "reports-consumer" }
    market-data       = { namespace = "indus", name = "market-data" }
    research-worker   = { namespace = "indus", name = "research-worker" }
    database-migrator = { namespace = "indus", name = "database-migrator" }
    web-publisher     = { namespace = "indus", name = "web-publisher" }
  }
}

data "aws_iam_policy_document" "workload_assume" {
  for_each = local.workload_service_accounts

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.workload_service_accounts

  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.workload_assume[each.key].json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "legacy_next" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.legacy_next.arn]
  }
}

resource "aws_iam_role_policy" "legacy_next" {
  name   = "${local.name}-legacy-next"
  role   = aws_iam_role.workload["legacy-next"].id
  policy = data.aws_iam_policy_document.legacy_next.json
}

data "aws_iam_policy_document" "load_balancer_controller" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  name   = "${local.name}-load-balancer-controller"
  role   = aws_iam_role.workload["aws-load-balancer-controller"].id
  policy = data.aws_iam_policy_document.load_balancer_controller.json
}

locals {
  workload_secret_access = {
    platform-api      = "platform-api"
    sidekiq           = "platform-api"
    platform-outbox   = "platform-api"
    reports-consumer  = "platform-api"
    market-data       = "market-data"
    research-worker   = "research-worker"
    database-migrator = "database-migration"
  }
  kafka_workloads = toset(["platform-api", "platform-outbox", "reports-consumer", "market-data"])
}

data "aws_iam_policy_document" "runtime_secret" {
  for_each = local.workload_secret_access

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.replacement[each.value].arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "runtime_secret" {
  for_each = local.workload_secret_access
  name     = "runtime-secret"
  role     = aws_iam_role.workload[each.key].id
  policy   = data.aws_iam_policy_document.runtime_secret[each.key].json
}

data "aws_iam_policy_document" "kafka" {
  for_each = local.kafka_workloads

  statement {
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [aws_msk_serverless_cluster.events.arn]
  }
  statement {
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData", "kafka-cluster:WriteData"]
    resources = ["${replace(aws_msk_serverless_cluster.events.arn, ":cluster/", ":topic/")}/*"]
  }
  statement {
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${replace(aws_msk_serverless_cluster.events.arn, ":cluster/", ":group/")}/*"]
  }
  statement {
    actions   = ["kafka-cluster:AlterTransactionalId", "kafka-cluster:DescribeTransactionalId"]
    resources = ["${replace(aws_msk_serverless_cluster.events.arn, ":cluster/", ":transactional-id/")}/*"]
  }
}

resource "aws_iam_role_policy" "kafka" {
  for_each = local.kafka_workloads
  name     = "kafka"
  role     = aws_iam_role.workload[each.key].id
  policy   = data.aws_iam_policy_document.kafka[each.key].json
}

data "aws_iam_policy_document" "redis" {
  statement {
    actions   = ["elasticache:Connect"]
    resources = [aws_elasticache_serverless_cache.application.arn, aws_elasticache_user.application.arn]
  }
}

resource "aws_iam_role_policy" "redis" {
  for_each = toset(["platform-api", "sidekiq"])
  name     = "redis"
  role     = aws_iam_role.workload[each.key].id
  policy   = data.aws_iam_policy_document.redis.json
}

data "aws_iam_policy_document" "artifact_access" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.data["artifacts"].arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data["artifacts"].arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "artifact_access" {
  for_each = toset(["platform-api", "research-worker", "sidekiq"])
  name     = "artifacts"
  role     = aws_iam_role.workload[each.key].id
  policy   = data.aws_iam_policy_document.artifact_access.json
}

data "aws_iam_policy_document" "web_publish" {
  statement {
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.data["web"].arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data["web"].arn]
  }
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.this.arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "web_publish" {
  name   = "web-publish"
  role   = aws_iam_role.workload["web-publisher"].id
  policy = data.aws_iam_policy_document.web_publish.json
}
