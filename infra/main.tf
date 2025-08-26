terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Use default VPC and its subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "selected" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  # Prefer public subnets for ALB + Fargate demo
  public_subnet_ids = [for s in data.aws_subnet.selected : s.id if s.map_public_ip_on_launch]
  private_subnet_ids = [for s in data.aws_subnet.selected : s.id if !s.map_public_ip_on_launch]
  app_name = var.app_name
}

resource "random_pet" "suffix" {}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.app_name}-${random_pet.suffix.id}"
  retention_in_days = 7
}


resource "aws_ecr_repository" "app" {
  name                 = local.app_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "envoy" {
  name                 = "${local.app_name}-envoy"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "traefik" {
  name                 = "${local.app_name}-traefik"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.app_name}-exec-${random_pet.suffix.id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "this" {
  name = "${local.app_name}-cluster-${random_pet.suffix.id}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.app_name}-alb-${random_pet.suffix.id}"
  description = "ALB SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "service" {
  name        = "${local.app_name}-svc-${random_pet.suffix.id}"
  description = "Service SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "from ALB"
    from_port   = 10000
    to_port     = 10000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb" "this" {
  name               = "${local.app_name}-${random_pet.suffix.id}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = length(local.public_subnet_ids) > 0 ? local.public_subnet_ids : data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "this" {
  name_prefix = "tg-"
  port     = 10000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }

  health_check {
    enabled             = true
    interval            = 20
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${local.app_name}-${random_pet.suffix.id}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = local.app_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true
      cpu       = 896
      memory    = 4096
      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = local.app_name
        }
      }
      environment = [
        { name = "JAVA_OPTS", value = "-XX:+UseZGC" }
      ]
    },
    {
      name      = "traefik"
      image     = "${aws_ecr_repository.traefik.repository_url}:${var.traefik_image_tag}"
      essential = true
      cpu       = 128
      memory    = 256
      portMappings = [
        { containerPort = 10000, hostPort = 10000, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "traefik"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = "${local.app_name}-svc-${random_pet.suffix.id}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = length(local.public_subnet_ids) > 0 ? local.public_subnet_ids : data.aws_subnets.default.ids
    security_groups = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "traefik"
    container_port   = 10000
  }

  depends_on = [aws_lb_listener.http]
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}


