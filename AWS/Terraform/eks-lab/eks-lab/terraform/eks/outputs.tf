output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = var.region
}

# Comando pronto pra atualizar seu ~/.kube/config.
# Depois disso o Lens/kubelens enxerga o cluster automaticamente.
output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# Use pra achar o hostname do LB depois do deploy do app:
# kubectl get svc -A | grep LoadBalancer
output "next_step_get_lb" {
  value = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
