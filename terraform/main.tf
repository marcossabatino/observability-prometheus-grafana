module "vpc" {
  source = "./modules/vpc"

  region              = var.region
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  cluster_name        = var.cluster_name
  availability_zones  = data.aws_availability_zones.available.names
}

module "eks" {
  source = "./modules/eks"

  region              = var.region
  environment         = var.environment
  cluster_name        = var.cluster_name

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids

  node_instance_type  = var.node_instance_type
  node_desired_count  = var.node_desired_count
  node_min_count      = var.node_min_count
  node_max_count      = var.node_max_count
  enable_spot         = var.enable_spot_instances
}

data "aws_availability_zones" "available" {
  state = "available"
}
