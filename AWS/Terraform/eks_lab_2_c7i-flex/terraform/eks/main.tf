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

  # Cria o OIDC provider do cluster, necessário pra IRSA (ex: EBS CSI role).
  # Na v20 já vem true por padrão; deixo explícito pra clareza.
  enable_irsa = true

  # Dá ao criador (você/CI) acesso admin automático via Access Entries.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.instance_types

      min_size     = var.node_min
      max_size     = var.node_max
      desired_size = var.node_desired

      # Free Plan não permite SPOT; usa a variável (default ON_DEMAND).
      capacity_type = var.capacity_type
    }
  }
}

# ---------- IRSA para o EBS CSI driver ----------
# O addon aws-ebs-csi-driver roda como pods que precisam falar com a API de
# EBS da AWS. Sem essa role o addon trava em CREATING e dá timeout.
# attach_ebs_csi_policy=true já anexa a policy gerenciada AmazonEBSCSIDriverPolicy.
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${var.cluster_name}-ebs-csi-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ---------- AWS Load Balancer Controller ----------
# Sem este controller, um Service type=LoadBalancer (como o do ingress-nginx)
# fica preso em <pending> pra sempre: ninguém escuta o pedido pra criar o NLB
# na AWS. As versões recentes do EKS NÃO trazem mais o provisionamento embutido.
# attach_load_balancer_controller_policy=true anexa a policy oficial.
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                              = "${var.cluster_name}-lb-controller-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"
  timeout    = 600

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  # Reusa o ServiceAccount criado pela IRSA acima (não deixa o chart criar outro).
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_irsa.iam_role_arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [module.eks]
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

  # Espera o release ficar pronto (inclui o NLB). 600s dá margem caso a AWS
  # demore a provisionar o NLB; o padrão de 300s às vezes é apertado.
  timeout = 600

  # Provisiona um NLB AWS automaticamente via service type LoadBalancer.
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
  # internet-facing = NLB com IP público, acessível pela internet.
  # Sem isso, o controller cria um NLB interno (IP 10.x.x.x), que só
  # responde de dentro da VPC. Funcional so se nao tiver nada exposto pra internet como Airflow.
    set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  # Precisa do LB controller já instalado, senão o Service fica <pending>.
  depends_on = [module.eks, helm_release.aws_lb_controller]
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
