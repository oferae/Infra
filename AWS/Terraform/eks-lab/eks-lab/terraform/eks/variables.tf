variable "region" {
  type    = string
  default = "eu-central-1" # Frankfurt - perto de Hof
}

variable "cluster_name" {
  type    = string
  default = "eks-lab"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

# Menores instâncias viáveis pro lab. t3.small = 2 vCPU / 2GB.
# Se faltar memória pro ingress + datadog, suba pra t3.medium.
variable "instance_types" {
  type    = list(string)
  default = ["t3.small"]
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
