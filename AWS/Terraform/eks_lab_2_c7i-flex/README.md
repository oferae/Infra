# EKS Lab

Lean AWS Lab: EKS cluster with ingress + load balancing, Datadog agents, app that shows the pod that responded, and a serverless hello-world. All via Terraform + CI/CD (GitHub Actions or Azure DevOps).

## What is build here:

| Component | Where | What does |
|---|---|---|
| VPC + EKS (2–4 nós t3.small SPOT) | `terraform/eks` | managed Kubernetes Cluster |
| ingress-nginx (ou traefik) | helm via TF | provisioning an ALB Cluster directly |
| Datadog agent + cluster agent | helm via TF | métrics, logs and APM from this cluster |
| `whoami` (3 réplicas) | `k8s/whoami.yaml` | shows pod hostname/IP on each refresh = sees LB alternating there |
| hello-world | `terraform/app-lambda` | Lambda + API Gateway HTTP, return a JSON |

## Exec order (manual for deployment)

```bash
# 0. credentials AWS (aws confugure, adn your IAM key) + DATADOG_API_KEY
export TF_VAR_datadog_api_key="yourdatadogkey"

# 1. cluster
cd terraform/eks
terraform init && terraform apply

# 2. kubeconfig output gives you the kubeconfig setup and accessing the cluster directly
aws eks update-kubeconfig --region us-east-1 --name eks-lab

# 3. app whoami
kubectl apply -f ../../k8s/namespace.yaml
kubectl apply -f ../../k8s/whoami.yaml

# 4. get the hostname of the load balancer
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# opens in the browser and refreshes: the "Hostname" field changes between the 3 pods

# 5. serverless
cd ../app-lambda
terraform init && terraform apply
terraform output hello_url   # curl nessa URL
```

In CI it's the same automated sequence — see `.github/workflows/deploy.yml` or `azure-pipelines/`.

## Lens / kubelens

After `update-kubeconfig`, the cluster already appears in Lens automatically (it reads `~/.kube/config`). If you run the CI on a machine other than yours, copy the context:

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-lab
# Lens > Catalog > o cluster "eks-lab" aparece. Enable Lens metrics
# or use Datadog data that is already being collected.
```

## Datadog

The API key goes like `TF_VAR_datadog_api_key` (env var / secret do CI), never commited. The chart installs node agent (DaemonSet) + cluster agent, with logs and APM connected. In the Datadog demo: **Infrastructure > Kubernetes** e **Containers** populate the info in few minutes...

## costs for the lab !!

- **EKS control plane: ~US$ 0,10/h** (~US$ 73/mês) e roda mesmo sem nós. Não dá pra desligar sem `terraform destroy`.
- 2× t3.medium cents/hour
- NAT Gateway: ~US$ 0,045/h + trafic
- 2× NLB (ingress): ~US$ 0,025/h each.

**Dont forget `terraform destroy` on each directories eks/lambda when the session finishes.** For a lab that runs for just a few hours, the cost is just a few dollars; forgetting it turned on for the whole month costs more than US$ 100.

```bash
cd terraform/eks && terraform destroy
cd terraform/app-lambda && terraform destroy
```

## Quick adjusts

- Memory outage (datadog + ingress uses too much RAM): change `instance_types` to `["t3.large or xlarge"]`.
- Want change traefik: `terraform apply -var ingress_controller=traefik` (and adjust the `ingressClassName` in whoami.yaml).
- Disable Datadog: `-var enable_datadog=false`.
- Remote state: uncomment the `backend "s3"` block in `versions.tf` (essential if the CI and you share state). or maybe you want versioning this guy to protect that.
