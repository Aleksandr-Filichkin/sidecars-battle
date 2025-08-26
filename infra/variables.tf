variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "echo"
}

variable "image_tag" {
  description = "Tag to use for the container image in ECR"
  type        = string
  default     = "latest"
}

variable "envoy_image_tag" {
  description = "Tag for Envoy sidecar image"
  type        = string
  default     = "latest"
}

variable "traefik_image_tag" {
  description = "Tag for Traefik sidecar image"
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Number of tasks"
  type        = number
  default     = 1
}

variable "task_cpu" {
  description = "CPU units for task (e.g., 256, 512, 1024)"
  type        = string
  default     = "1024"
}

variable "task_memory" {
  description = "Memory for task in MiB (e.g., 512, 1024)"
  type        = string
  default     = "4096"
}

// traefik_image no longer required since Traefik was removed


