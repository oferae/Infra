variable "region" {
  type    = string
  default = "us-east-1" # USA
}

variable "cluster_name" {
  type    = string
  default = "eks-lab"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

# Conta Free Plan (criada após 15/jul/2025) só permite estes tipos:
# t3.micro, t3.small, t4g.micro, t4g.small, c7i-flex.large, m7i-flex.large.
# c7i-flex.large = 2 vCPU / 4GB. Elegível no Free Plan e suficiente pro lab.
# Se faltar memória, m7i-flex.large (2 vCPU / 8GB) é a próxima opção elegível.
variable "instance_types" {
  type    = list(string)
  default = ["c7i-flex.large"]
}

# Free Plan geralmente NÃO permite SPOT — use ON_DEMAND. Em conta paga,
# SPOT derruba o custo, mas pode ser reclamada a qualquer momento.
variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 4
}

variable "node_desired" {
  type    = number
  default = 2
}

# true = Datadog via Helm. Coloque a API key como var de ambiente / secret.
variable "enable_datadog" {
  type    = bool
  default = true
}

variable "datadog_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

# Datacenter do Datadog. Tem que bater com o domínio onde você loga.
# us5 -> "us5.datadoghq.com" | US1 -> "datadoghq.com" | EU -> "datadoghq.eu"
variable "datadog_site" {
  type    = string
  default = "us5.datadoghq.com"
}

variable "ingress_controller" {
  type    = string
  default = "nginx" # ou "traefik"
}
