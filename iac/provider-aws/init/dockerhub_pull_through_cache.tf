# --- Docker Hub Pull-Through Cache ---
# Mirrors Docker Hub via ECR to avoid rate limits.
# Requires Docker Hub credentials stored in Secrets Manager.

resource "aws_ecr_pull_through_cache_rule" "dockerhub" {
  count = var.enable_dockerhub_pull_through_cache ? 1 : 0

  ecr_repository_prefix = "dockerhub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.dockerhub_pull_through_credentials[0].arn
}

# ECR requires a specific secret format for pull-through cache credentials
resource "aws_secretsmanager_secret" "dockerhub_pull_through_credentials" {
  count = var.enable_dockerhub_pull_through_cache ? 1 : 0

  name = "ecr-pullthroughcache/docker-hub/${var.prefix}credentials"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "dockerhub_pull_through_credentials" {
  count = var.enable_dockerhub_pull_through_cache ? 1 : 0

  secret_id = aws_secretsmanager_secret.dockerhub_pull_through_credentials[0].id
  secret_string = jsonencode({
    username    = data.aws_secretsmanager_secret_version.dockerhub_username[0].secret_string
    accessToken = data.aws_secretsmanager_secret_version.dockerhub_password[0].secret_string
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

data "aws_secretsmanager_secret_version" "dockerhub_username" {
  count      = var.enable_dockerhub_pull_through_cache ? 1 : 0
  secret_id  = aws_secretsmanager_secret.dockerhub_username.id
  depends_on = [aws_secretsmanager_secret_version.dockerhub_username]
}

data "aws_secretsmanager_secret_version" "dockerhub_password" {
  count      = var.enable_dockerhub_pull_through_cache ? 1 : 0
  secret_id  = aws_secretsmanager_secret.dockerhub_password.id
  depends_on = [aws_secretsmanager_secret_version.dockerhub_password]
}

# Lifecycle policy to clean up cached images after 90 days
resource "aws_ecr_lifecycle_policy" "dockerhub_cache_cleanup" {
  count = var.enable_dockerhub_pull_through_cache ? 1 : 0

  repository = "dockerhub/*"

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire cached Docker Hub images after 90 days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 90
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  depends_on = [aws_ecr_pull_through_cache_rule.dockerhub]
}
