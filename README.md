# Roadpass Digital DevOps Assignment

This repository is my submission for the Roadpass Digital DevOps take-home exercise. It covers all three required sections — VPC infrastructure, a Packer/Ansible/Terraform EC2 application stack, and a Helm + GitHub Actions deployment pipeline — with additional attention to operational concerns that matter in a real engineering environment: remote state management, billing visibility, tagging strategy, and IAM least privilege.

As this is just a demo environment, I didn't mind putting everything into a single repo. However, in practice, this is an anti-pattern. Ideally, I'd have a repo for managing the packer config that runs nightly or weekly at least. We could version the instance with the datetime. That would let us pick and choose versions of the packed image for future EC2 builds. 

As for Helm, this is IMHO, the best way to package and manage containers at scale. Kubernetes won the war, and Helm is the flagship. As above, this should be in a separate repo. If you have a LOT of environments, like 20+, then you could bring in something like ArgoCD. However, if you have fewer than 10, then github actions worfklows will be more than enough.

For next steps I would include logging and alerting. Central logging systems like Datadog are priceless. Alerting is all about reducing the time between action and feedback. The shorter the feedback loop, the faster the iteration. 

Admittedly, most of this was written with Claude Code under my guidance. Fortunately, I have 20 years experience of building systems and managing workflows like these without so much as a random word generator... 

---

## Architecture Overview

```
                            172.16.0.0/16
  ┌─────────────────────────────────────────────────────────────┐
  │                         Staging VPC                         │
  │                                                             │
  │   us-east-1a                    us-east-1b                  │
  │  ┌──────────────────┐          ┌──────────────────┐         │
  │  │  Public Subnets  │          │  Public Subnets  │         │
  │  │  172.16.0.0/20   │          │  172.16.32.0/20  │         │
  │  │  172.16.16.0/20  │          │  172.16.48.0/20  │         │
  │  │   [ALB nodes]    │          │   [ALB nodes]    │         │
  │  │      |NAT GW     │          │      |NAT GW     │         │
  │  └──────┼───────────┘          └──────┼───────────┘         │
  │         |                             |                      │
  │  ┌──────┼───────────┐          ┌──────┼───────────┐         │
  │  │  Private Subnets │          │  Private Subnets │         │
  │  │  172.16.64.0/20  │          │  172.16.96.0/20  │         │
  │  │  172.16.80.0/20  │          │ 172.16.112.0/20  │         │
  │  │   [EC2 + ASG]    │          │   [EC2 + ASG]    │         │
  │  └──────────────────┘          └──────────────────┘         │
  │                                                             │
  │  VPC Endpoints: S3 (Gateway) + SSM/ssmmessages/ec2messages  │
  └─────────────────────────────────────────────────────────────┘
           |                                |
        [IGW]                            [IGW]
           |
     Internet / ALB DNS
```

**Traffic flow:** Internet → ALB (public subnets) → EC2 instances (private subnets) via target group.
**Egress from private subnets:** NAT Gateway (one per AZ) → Internet Gateway.
**SSM access:** Instances use the SSM VPC interface endpoints — no SSH or bastion required.

---

## Repository Structure

```
roadpass-exam/
├── bootstrap/                     # One-time: creates Terraform remote state backend
├── terraform/
│   ├── modules/vpc/               # Reusable VPC module
│   └── live/
│       ├── terragrunt.hcl         # Root: remote state config + universal tags
│       └── staging/
│           ├── vpc/               # Staging VPC deployment
│           ├── ec2-app/           # ASG + ALB + IAM stack
│           ├── billing-alarm/     # CloudWatch billing alert
│           └── github-oidc/       # GitHub Actions OIDC provider + IAM role
├── packer/
│   ├── nginx-ami.pkr.hcl          # Packer HCL2 build template
│   └── ansible/
│       ├── playbook-pack.yml      # Build-time provisioning
│       ├── playbook-fry.yml       # Launch-time provisioning
│       └── roles/
│           ├── pack/              # Install nginx, static page
│           └── fry/               # Apply userdata variables at launch
├── helm/nginx-app/                # Helm chart: Deployment + Service + Ingress + PDB
└── .github/workflows/
    └── deploy-helm.yml            # OIDC-based EKS deploy workflow
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.5.0 |
| Terragrunt | >= 0.55.0 |
| Packer | >= 1.10.0 |
| Ansible | >= 2.15.0 |
| Helm | >= 3.14.0 |
| AWS CLI | >= 2.x |

AWS credentials must be configured with permission to create VPCs, EC2 resources, IAM roles, and CloudWatch alarms.
An admin user called `roadpass-exam-admin` was created — using root credentials for day-to-day operations is an anti-pattern.

---

## Deploy Order

### Step 1 — Bootstrap Remote State (run once)

```bash
cd bootstrap
terraform init
terraform apply

# Note the outputs for use in live/terragrunt.hcl
terraform output tfstate_bucket_name
terraform output aws_account_id
```

The bucket name is already set in `terraform/live/terragrunt.hcl` (`roadpass-exam-tfstate-585445411780`). If you're reproducing this in a different account, update that value with the output of `terraform output tfstate_bucket_name`.

**Why this first?** Terraform state files must never be committed to git. The S3 backend with DynamoDB locking prevents concurrent applies from corrupting state — a critical operational requirement in any team environment.

---

### Step 2 — Deploy the VPC

```bash
cd terraform/live/staging/vpc
terragrunt init
terragrunt plan
terragrunt apply
```

This creates the full 172.16.0.0/16 network: 8 subnets across 2 AZs, IGW, 2 NAT Gateways, routing tables, SSM interface endpoints, and an S3 gateway endpoint.

---

### Step 3 — Deploy the GitHub OIDC Provider

```bash
cd terraform/live/staging/github-oidc
terragrunt init
terragrunt apply
```

This creates the IAM OIDC provider for `token.actions.githubusercontent.com` and the `github-oidc-eks-deploy` role trusted by GitHub Actions. The trust policy is scoped to `repo:technoe/roadpass-exam:*` — no other repository can assume this role.

After applying, add one secret to the GitHub repository's **`staging` environment** (Settings → Environments → staging → Environment secrets):

```
AWS_ACCOUNT_ID = <your account ID>
```

The workflow declares `environment: staging`, which is what makes GitHub inject this secret. A repo-level secret would not be available to environment-scoped jobs.

---

### Step 4 — Build the AMI with Packer

```bash
cd packer
packer init nginx-ami.pkr.hcl
packer build nginx-ami.pkr.hcl
```

Packer will:
1. Launch a temporary t3.micro from the latest Amazon Linux 2023 AMI
2. Run the **pack** Ansible role: install nginx, deploy the static HTML page, enable the service
3. Stop the instance and create an AMI snapshot
4. Tag the AMI and clean up the temporary instance

Note the AMI ID from the output, then update `ami_id` in `terraform/live/staging/ec2-app/terragrunt.hcl`.

#### The Pack/Fry Pattern

This is an immutable infrastructure pattern for AMI-based deployments:

- **Pack phase** (build time): Everything that is environment-agnostic is baked in — package installs, base configuration, the binary itself. The AMI is sealed after this point. The same AMI is promoted through staging then production.

- **Fry phase** (launch time): Environment-specific variables are injected via EC2 userdata. Terraform renders `userdata.sh.tpl` with values like `server_name` and `environment`, writes them to `/etc/nginx-fry-vars.env`, and reloads nginx with the rendered config. This keeps the AMI generic while making each instance aware of its context.

---

### Step 5 — Deploy the EC2 App Stack

> **Note:** This step requires EC2 launch permissions. On a brand new AWS account, EC2 may be temporarily blocked pending identity verification. If `packer build` returns `Blocked: This account is currently blocked`, open a support case at the URL in the error message — resolution is typically within a few hours.

```bash
cd terraform/live/staging/ec2-app
terragrunt init
terragrunt plan
terragrunt apply

# Get the ALB URL
terragrunt output alb_dns_name
```

Then verify: `curl http://<alb_dns_name>/health` should return `healthy`.

---

### Step 6 — Deploy the Billing Alarm

```bash
cd terraform/live/staging/billing-alarm
# Edit terragrunt.hcl to set your email address first
terragrunt apply
```

AWS will send a confirmation email to the address you configured. You must click the confirmation link to activate the SNS subscription.

---

## Helm Chart — nginx-app

The chart creates a Deployment, ClusterIP Service, Ingress, and PodDisruptionBudget.

### Render the templates (no cluster needed)

```bash
helm template nginx-app ./helm/nginx-app \
  --values ./helm/nginx-app/values.yaml
```

### Deploy to a cluster

```bash
helm upgrade --install nginx-app ./helm/nginx-app \
  --values ./helm/nginx-app/values.yaml \
  --namespace staging \
  --create-namespace \
  --atomic \
  --timeout 5m
```

The `--atomic` flag rolls back automatically if the deployment fails, and `--wait` blocks until all pods are ready.

The ingress `className` in `values.yaml` defaults to `nginx`. Set it to `alb` and add the appropriate ALB controller annotations for AWS Load Balancer Controller.

---

## GitHub Actions — OIDC Deploy

The workflow in `.github/workflows/deploy-helm.yml` deploys the Helm chart to a staging EKS cluster using GitHub's OIDC provider — no long-lived AWS credentials are stored in GitHub Secrets.

### One-time OIDC trust setup

The IAM OIDC provider and role are managed by the `terraform/live/staging/github-oidc/` stack (see Step 3 in Deploy Order). After applying, set one secret in the GitHub **`staging` environment** (not a repo-level secret):

```
AWS_ACCOUNT_ID = <your AWS account ID>
```

The workflow job declares `environment: staging`, which both injects the environment variable and changes the GitHub OIDC `sub` claim to `repo:technoe/roadpass-exam:environment:staging`. The trust policy uses a wildcard (`repo:technoe/roadpass-exam:*`) to match both environment-scoped and branch-scoped jobs. Using separate accounts for each environment reduces the chance that we'll accidentally deploy to the wrong environment and reduces the damage that can be done should only the testing/uat environment credentials become compromised. I created an AWS account to verify the OIDC authorziation config. You can see the OIDC step in the github actions workflow. 

### How OIDC authentication works

1. GitHub Actions requests a JWT from GitHub's OIDC provider, signed with claims about the repo, branch, and workflow.
2. `aws-actions/configure-aws-credentials` calls `sts:AssumeRoleWithWebIdentity`, presenting the JWT.
3. AWS validates the JWT signature and evaluates the trust policy conditions (`sub`, `aud`).
4. AWS returns short-lived credentials (1-hour TTL) scoped to the role's permissions.
5. No secret rotation needed. If a repo is compromised, revoking the IAM role is the kill switch.

---

## IAM & Security Approach

### EC2 Instance Role

The instance role has exactly two policies:

| Policy | Why |
|---|---|
| `AmazonSSMManagedInstanceCore` (AWS managed) | Enables SSM Session Manager — instances are accessible without SSH, no key pairs, full audit trail in CloudTrail |
| Inline S3 read (scoped to one bucket) | Least-privilege: `s3:GetObject` + `s3:ListBucket` on a named bucket only |

There are no `*` actions, no wildcard resources, and no `AdministratorAccess`. The instance cannot escalate its own privileges.

### Why SSM over SSH

- No key pair management or rotation
- Every session is logged to CloudTrail (who connected, when, what commands)
- Works through the VPC endpoints — instances don't need internet access to be reachable
- Port 22 can be removed from security groups entirely in a hardened environment

### VPC Endpoint Security Group

The SSM interface endpoints accept only port 443 TCP from within the VPC CIDR (`172.16.0.0/16`). Nothing from outside the VPC can reach the endpoints.

---

## Cost Considerations

Running this architecture continuously in us-east-1 will cost approximately:

| Resource | Approx. Monthly Cost |
|---|---|
| 2x NAT Gateways (~$0.045/hr each) | ~$65 |
| 2x t3.micro EC2 (on-demand) | ~$17 |
| 1x Application Load Balancer | ~$16 |
| 3x SSM VPC Interface Endpoints | ~$21 |
| S3 + DynamoDB remote state | <$1 |
| **Total (approx.)** | **~$120/month** |

**Cost reduction options for a non-production staging environment:**

- Use a single NAT Gateway (lose AZ redundancy, save ~$32/month) — acceptable for staging
- Use Reserved Instances or Savings Plans for EC2 if the environment runs continuously
- Delete the SSM endpoints and allow SSM traffic through NAT GW instead (tradeoff: loses private endpoint security)
- Switch `t3.micro` to `t4g.micro` (ARM, ~20% cheaper) if workload is ARM-compatible

The billing alarm at $50 will alert before costs get out of hand during testing.

To analyze actual spend by project, enable the `Project` tag in AWS Cost Explorer:
**Billing > Cost Explorer > Tags > Activate user-defined cost allocation tags > `Project`**

---

## Known Extensions

These are not in scope for this submission but worth noting:

- **SSL/TLS via ACM**: Add `aws_acm_certificate` + DNS validation + HTTPS listener on the ALB. Requires a domain you control.
- **EKS cluster**: The Helm chart and GitHub Actions workflow are ready; only the cluster itself is absent.
- **Multi-account Terragrunt**: The root `terragrunt.hcl` is structured to support an `account-id/region/environment/` hierarchy for multi-account orgs.
- **Auto-rotate AMI**: A scheduled GitHub Actions workflow or Lambda that runs `packer build` weekly and triggers an ASG instance refresh with the new AMI ID.
