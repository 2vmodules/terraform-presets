locals {
  cache_envs = {
    CACHE_DRIVER     = "redis"
    SESSION_DRIVER   = "redis"
    REDIS_HOST       = var.redis_enabled ? format("%s://%s", "tls", module.redis[0].endpoint) : ""
    QUEUE_CONNECTION = "redis"
  }
  cache_secrets = {
    REDIS_PASSWORD = var.redis_enabled ? module.redis[0].auth_token_ssm_arn : ""
  }
  db_envs = {
    DB_CONNECTION = "pgsql"
    DB_HOST       = var.postgres_enabled ? var.postgres_rds_type == "rds" ? module.postgres[0].rds_instance_address[0] : module.postgres[0].cluster_endpoint[0] : ""
    DB_PORT       = "5432"
    DB_DATABASE   = var.postgres_database_name
    DB_USERNAME   = var.postgres_master_username
  }
  db_secrets = {
    DB_PASSWORD = var.postgres_enabled ? module.postgres[0].rds_instance_master_password_ssm_arn : ""
  }

  # Injecting infra-level db & cache credentials
  final_ecs_containers = [
    for container in var.ecs_containers : {
      name                 = container.name
      image                = container.image
      command              = container.command
      cpu                  = container.cpu
      memory               = container.memory
      min_count            = container.min_count
      max_count            = container.max_count
      target_cpu_threshold = container.target_cpu_threshold
      target_mem_threshold = container.target_mem_threshold
      path                 = container.path
      priority             = container.priority
      port                 = container.port
      envs                 = merge(container.envs, local.db_envs, local.cache_envs)
      secrets              = merge(container.secrets, local.db_secrets, local.cache_secrets)
      health_check         = container.health_check
      metrics              = container.metrics
    }
  ]

  # # Forming a list of buckets for public access via CloudFront
  # public_bucket_keys     = [for i, bucket in var.s3_bucket_list : i if bucket.public == true]
  # public_bucket_keys_map = tomap({ for k, v in local.public_bucket_keys : v => k })
  # public_bucket_list     = [for key in local.public_bucket_keys_map : lookup(var.s3_bucket_list, key)]

  public_bucket_list = [
    for bucket in var.s3_bucket_list : {
      name        = bucket.name
      domain_name = "${bucket.name}.s3.${var.region}.amazonaws.com"
      path        = bucket.path
    } if bucket.public
  ]

}

module "vpc" {
  source = "../../aws/vpc"

  region = var.region
  env    = var.env

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

}

module "alb" {
  source = "../../aws/alb"

  providers = {
    aws.main      = aws.main
    aws.us_east_1 = aws.us_east_1
  }

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  domain_name     = var.domain_name
  cdn_domain_name = "cdn.${var.domain_name}"

  vpc_id      = module.vpc.vpc_id
  vpc_subnets = module.vpc.public_subnets

  idle_timeout = var.alb_idle_timeout

  #cdn_bucket_names = [module.s3[1].s3_bucket_bucket_regional_domain_name]
  cdn_enabled         = var.cdn_enabled
  cdn_buckets         = local.public_bucket_list
  cdn_optimize_images = var.cdn_optimize_images

}

module "ecr" {
  count  = var.ecr_enabled == true ? 1 : 0
  source = "../../aws/ecr"

  providers = {
    aws.main      = aws.main
    aws.us_east_1 = aws.us_east_1
  }

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  ecr_repositories = var.ecr_repositories

}

module "ecs" {
  count  = var.ecs_enabled == true ? 1 : 0
  source = "../../aws/ecs"

  providers = {
    aws.main      = aws.main
    aws.us_east_1 = aws.us_east_1
  }

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  vpc_id                  = module.vpc.vpc_id
  vpc_subnets             = module.vpc.private_subnets
  vpc_private_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  alb_security_group      = module.alb.alb_aws_security_group_id
  alb_listener_arn        = module.alb.alb_listener_https_arn

  cluster_name = var.ecs_cluster_name
  containers   = local.final_ecs_containers

}

module "ecs-monitor" {
  count  = var.ecs_monitoring_enabled ? 1 : 0
  source = "../../aws/ecs-monitor"

  providers = {
    aws.main      = aws.main
    aws.us_east_1 = aws.us_east_1
  }

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  vpc_id                  = module.vpc.vpc_id
  vpc_subnets             = module.vpc.private_subnets
  vpc_private_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  alb_security_group      = module.alb.alb_aws_security_group_id
  alb_listener_arn        = module.alb.alb_listener_https_arn

  ecs_cluster_id                     = module.ecs[0].ecs_cluster_id
  ecs_cloudwatch_group_name          = module.ecs[0].ecs_cloudwatch_group_name
  ecs_security_group_ids             = module.ecs[0].ecs_security_group_ids
  ecs_service_discovery_namespace_id = module.ecs[0].ecs_service_discovery_namespace_id
  ecs_task_role_arn                  = module.ecs[0].ecs_task_role_arn
  ecs_exec_role_arn                  = module.ecs[0].ecs_task_exec_role_arn


}

module "postgres" {
  count  = var.postgres_enabled == true ? 1 : 0
  source = "../../aws/postgres"

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  vpc_id                  = module.vpc.vpc_id
  vpc_private_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  vpc_subnets             = module.vpc.database_subnets
  vpc_subnet_group_name   = module.vpc.database_subnet_group_name

  rds_type                      = var.postgres_rds_type
  engine_version                = var.postgres_engine_version
  family                        = var.postgres_family
  instance_class                = var.postgres_instance_class
  allocated_storage             = var.postgres_allocated_storage
  max_allocated_storage         = var.postgres_max_allocated_storage
  rds_cluster_parameters        = var.postgres_rds_cluster_parameters
  rds_db_parameters             = var.postgres_rds_db_parameters
  allow_vpc_cidr_block          = var.postgres_allow_vpc_cidr_block
  allow_vpc_private_cidr_blocks = var.postgres_allow_vpc_private_cidr_blocks
  extra_allowed_cidr_blocks     = var.postgres_extra_allowed_cidr_blocks
  backup_retention_period       = var.backup_retention_period
  preferred_maintenance_window  = var.postgres_preferred_maintenance_window
  preferred_backup_window       = var.postgres_preferred_backup_window
  master_username               = var.postgres_master_username
  database_name                 = var.postgres_database_name
  database_user_map             = var.postgres_database_user_map
}

resource "aws_iam_role_policy_attachment" "ecs_task_postgres_policy" {
  count      = var.postgres_enabled == true ? 1 : 0
  role       = module.ecs[0].ecs_task_exec_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess"
}

module "redis" {
  count  = var.redis_enabled == true ? 1 : 0
  source = "../../aws/redis"

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  vpc_id                  = module.vpc.vpc_id
  vpc_subnets             = module.vpc.private_subnets
  vpc_private_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  cluster_size                         = var.redis_cluster_size
  instance_type                        = var.redis_instance_type
  engine_version                       = var.redis_engine_version
  family                               = var.redis_family
  cluster_mode_num_node_groups         = var.redis_cluster_mode_num_node_groups
  cluster_mode_enabled                 = var.redis_cluster_mode_enabled
  automatic_failover_enabled           = var.redis_automatic_failover_enabled
  cluster_mode_replicas_per_node_group = var.redis_cluster_mode_replicas_per_node_group
  snapshot_retention_limit             = var.redis_snapshot_retention_limit
  kms_ssm_key_arn                      = var.redis_kms_ssm_key_arn
  allow_vpc_cidr_block                 = var.redis_allow_vpc_cidr_block
  allow_vpc_private_cidr_blocks        = var.redis_allow_vpc_private_cidr_blocks
  extra_allowed_cidr_blocks            = var.redis_extra_allowed_cidr_blocks

}

resource "aws_iam_role_policy_attachment" "ecs_task_redis_policy" {
  count      = var.redis_enabled == true ? 1 : 0
  role       = module.ecs[0].ecs_task_exec_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
}

module "ec2" {
  count  = var.bastion_enabled == true ? 1 : 0
  source = "../../aws/ec2"

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  vpc_id            = module.vpc.vpc_id
  private_subnet_id = module.vpc.private_subnets[0]
  public_subnet_id  = module.vpc.public_subnets[0]

  ssh_authorized_keys_secret = var.bastion_ssh_authorized_keys_secret
  allowed_tcp_ports          = ["22"]

}

module "s3" {
  for_each = { for idx, bucket in var.s3_bucket_list : idx => bucket }
  source   = "../../aws/s3"

  providers = {
    aws.main   = aws.main
    aws.backup = aws.backup
  }

  region = var.region
  env    = var.env
  tags   = var.tags

  name        = each.value["name"]
  public      = each.value["public"]
  replication = each.value["replication"]
}

module "cloudtrail" {
  count  = var.cloudtrail_enabled == true ? 1 : 0
  source = "../../aws/cloudtrail"

  region = var.region
  env    = var.env
  name   = var.name
  tags   = var.tags

  log_retention_days = var.cloudtrail_log_retention_days
}
