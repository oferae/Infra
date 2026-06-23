data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------- VPC ----------
# Single NAT gateway pra baratear (lab). Em prod seria 1 por AZ.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tags exigidas pelo EKS pra descoberta de subnets pelo LB controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }
}

# ---------- EKS ----------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  # Dá ao criador (você/CI) acesso admin automático via Access Entries.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    aws-ebs-csi-driver     = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.instance_types

      min_size     = var.node_min
      max_size     = var.node_max
      desired_size = var.node_desired

      # Spot derruba MUITO o custo do lab. Troque pra ON_DEMAND se quiser estabilidade.
      capacity_type = "SPOT"
    }
  }
}

# ---------- Ingress Controller ----------
resource "helm_release" "ingress_nginx" {
  count            = var.ingress_controller == "nginx" ? 1 : 0
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.2"

  # Provisiona um NLB AWS automaticamente via service type LoadBalancer.
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  depends_on = [module.eks]
}

resource "helm_release" "traefik" {
  count            = var.ingress_controller == "traefik" ? 1 : 0
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  namespace        = "traefik"
  create_namespace = true
  version          = "28.3.0"

  depends_on = [module.eks]
}

# ---------- Datadog ----------
resource "helm_release" "datadog" {
  count            = var.enable_datadog ? 1 : 0
  name             = "datadog"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  namespace        = "datadog"
  create_namespace = true
  version          = "3.70.5"

  set_sensitive {
    name  = "datadog.apiKey"
    value = var.datadog_api_key
  }
  set {
    name  = "datadog.site"
    value = var.datadog_site
  }
  # Cluster Agent + métricas de kube state + APM/logs
  set {
    name  = "clusterAgent.enabled"
    value = "true"
  }
  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }
  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }
  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  depends_on = [module.eks]
}
