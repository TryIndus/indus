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
