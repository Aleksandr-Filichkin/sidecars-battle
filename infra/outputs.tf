output "alb_url" {
  value       = "http://${aws_lb.this.dns_name}"
  description = "ALB URL"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR repository URL"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name"
}

output "ecs_service_name" {
  value       = aws_ecs_service.this.name
  description = "ECS service name"
}

output "envoy_ecr_repository_url" {
  value       = aws_ecr_repository.envoy.repository_url
  description = "Envoy ECR repository URL"
}

output "traefik_ecr_repository_url" {
  value       = aws_ecr_repository.traefik.repository_url
  description = "Traefik ECR repository URL"
}

