# EKS Lab

Lab AWS enxuto: cluster EKS com ingress + load balancing, agents Datadog, app que mostra o pod que respondeu, e um hello-world serverless. Tudo via Terraform + CI/CD (GitHub Actions ou Azure DevOps).

## O que sobe

| Componente | Onde | O que faz |
|---|---|---|
| VPC + EKS (2–4 nós t3.small SPOT) | `terraform/eks` | cluster Kubernetes gerenciado |
| ingress-nginx (ou traefik) | helm via TF | provisiona um NLB AWS automaticamente |
| Datadog agent + cluster agent | helm via TF | métricas, logs e APM do cluster |
| `whoami` (3 réplicas) | `k8s/whoami.yaml` | mostra hostname/IP do pod a cada refresh = vê o LB alternando |
| hello-world | `terraform/app-lambda` | Lambda + API Gateway HTTP, retorna JSON |

## Ordem de execução (manual)

```bash
# 0. credenciais AWS no ambiente + DATADOG_API_KEY
export TF_VAR_datadog_api_key="sua-key-do-datadog-demo"

# 1. cluster
cd terraform/eks
terraform init && terraform apply

# 2. kubeconfig (output já te dá o comando pronto)
aws eks update-kubeconfig --region eu-central-1 --name eks-lab

# 3. app whoami
kubectl apply -f ../../k8s/namespace.yaml
kubectl apply -f ../../k8s/whoami.yaml

# 4. pega o hostname do load balancer
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# abre no browser e dá refresh: o campo "Hostname" muda entre os 3 pods

# 5. serverless
cd ../app-lambda
terraform init && terraform apply
terraform output hello_url   # curl nessa URL
```

No CI é a mesma sequência automatizada — veja `.github/workflows/deploy.yml` ou `azure-pipelines/`.

## Lens / kubelens

Depois do `update-kubeconfig`, o cluster já aparece no Lens automaticamente (ele lê o `~/.kube/config`). Se rodar o CI numa máquina diferente da sua, copie o contexto:

```bash
aws eks update-kubeconfig --region eu-central-1 --name eks-lab
# Lens > Catalog > o cluster "eks-lab" aparece. Ative os metrics do Lens
# ou use os dados do Datadog que já estão sendo coletados.
```

## Datadog

A API key vai como `TF_VAR_datadog_api_key` (env var / secret do CI), nunca commitada. O chart instala node agent (DaemonSet) + cluster agent, com logs e APM ligados. No Datadog demo: **Infrastructure > Kubernetes** e **Containers** já populam em poucos minutos.

## Custos (atenção — é o ponto sensível do lab)

- **EKS control plane: ~US$ 0,10/h** (~US$ 73/mês) e roda mesmo sem nós. Não dá pra desligar sem `terraform destroy`.
- 2× t3.small SPOT: centavos/hora.
- NAT Gateway: ~US$ 0,045/h + tráfego — costuma ser o segundo maior custo.
- 2× NLB (ingress): ~US$ 0,025/h cada.

**Sempre `terraform destroy` nos dois diretórios quando terminar a sessão.** Para um lab ligado só algumas horas o custo fica em poucos dólares; esquecer ligado o mês inteiro passa de US$ 100.

```bash
cd terraform/eks && terraform destroy
cd terraform/app-lambda && terraform destroy
```

## Ajustes rápidos

- Faltou memória (datadog + ingress comem RAM): troque `instance_types` pra `["t3.medium"]`.
- Quer traefik: `terraform apply -var ingress_controller=traefik` (e ajuste o `ingressClassName` no whoami.yaml).
- Sem Datadog: `-var enable_datadog=false`.
- State remoto: descomente o bloco `backend "s3"` em `versions.tf` (essencial se o CI e você compartilham state).
