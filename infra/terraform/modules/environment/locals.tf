data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}
data "aws_route53_zone" "public" {
  name         = var.route53_zone_name
  private_zone = false
}

locals {
  name                      = "${var.project}-${var.environment}"
  production                = var.environment == "production"
  azs                       = slice(data.aws_availability_zones.available.names, 0, 2)
  primary_az                = local.azs[0]
  primary_private_subnet_id = aws_subnet.private[local.primary_az].id
  public_subnet_cidrs       = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index)]
  private_subnet_cidrs      = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index + 4)]
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "TryIndus/indus"
  })
}
