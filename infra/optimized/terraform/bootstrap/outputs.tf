output "state_bucket" { value = aws_s3_bucket.state.id }
output "state_kms_key_arn" { value = aws_kms_key.bootstrap.arn }
output "terraform_role_arn" { value = aws_iam_role.terraform.arn }
output "release_role_arn" { value = aws_iam_role.release.arn }
output "ecr_repository_urls" { value = { for name, repository in aws_ecr_repository.images : name => repository.repository_url } }
