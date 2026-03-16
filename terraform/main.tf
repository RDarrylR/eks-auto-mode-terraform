data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Production: one per AZ for HA
  enable_dns_hostnames = true

  # Production: add VPC endpoints for ECR, S3, STS, CloudWatch
  # to reduce NAT gateway costs and keep traffic private

  # Tags for Auto Mode subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ------------------------------------------------------------------------------
# EKS Cluster with Auto Mode
# ------------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.project_name
  kubernetes_version  = var.cluster_version

  endpoint_public_access = true
  # UNCOMMENT for production: restrict to your IP ranges or use private-only access with VPN/bastion
  # cluster_endpoint_public_access_cidrs = ["YOUR_CIDR/32"]

  # Enable Auto Mode - this single block enables:
  #   - Managed Karpenter (compute)
  #   - Managed EBS CSI driver (storage_config derived from compute_config.enabled)
  #   - Managed ALB/NLB Controller (elastic_load_balancing derived from compute_config.enabled)
  #   - Managed VPC CNI, kube-proxy, CoreDNS (bootstrap_self_managed_addons hardcoded false)
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Auto Mode IAM resources - creates the node IAM role with required policies
  # Both flags must be true: create_node_iam_role creates the eks_auto role,
  # create_auto_mode_iam_resources attaches the Auto Mode cluster policies
  create_node_iam_role           = true
  create_auto_mode_iam_resources = true

  # Production: enable envelope encryption for Kubernetes secrets with KMS
  # cluster_encryption_config = {
  #   resources        = ["secrets"]
  #   provider_key_arn = aws_kms_key.eks.arn
  # }

  # Cluster access - grants the deploying identity cluster admin
  enable_cluster_creator_admin_permissions = true

  # Observability - CloudWatch Container Insights with Pod Identity
  addons = {
    metrics-server = {
      most_recent = true
    }
    amazon-cloudwatch-observability = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.cloudwatch.arn
        service_account = "cloudwatch-agent"
      }]
    }
  }
}
