# EKS Secured Container Deployment with CI/CD and Security Controls

## Overview
This project containerizes and deploys the osTicket web application to Amazon EKS using Terraform. It implements container image scanning, RBAC with least-privilege roles, Kubernetes network policies enforcing default-deny pod communication, and a CI/CD pipeline with integrated security scanning via Trivy and Checkov.

## Architecture

ECR — Private container registry with immutable tags, scan-on-push, and KMS encryption  
EKS — Managed Kubernetes cluster with 2 worker nodes across 2 AZs  
VPC — Public and private subnets; worker nodes in private subnets only  
CI/CD — GitHub Actions with OIDC federation, Trivy image scanning, Checkov IaC scanning  
Security — Namespace isolation, RBAC (developer/db-admin/security-auditor), network policies with default-deny  

## Prerequisites

- AWS account with CLI configured (aws configure or aws configure sso)  
- Terraform >= 1.5.0  
- Docker installed and running  
- kubectl installed  
- GitHub account  

## Project Structure
osticket-eks/
├── docker/  
│   ├── Dockerfile  
│   └── Dockerfile.mysql  
├── terraform/  
│   ├── main.tf  
│   ├── variables.tf  
│   ├── outputs.tf  
│   ├── vpc.tf  
│   ├── eks.tf  
│   ├── ecr.tf  
│   └── iam.tf  
├── kubernetes/  
│   ├── namespaces.yaml  
│   ├── mysql-deployment.yaml  
│   ├── mysql-service.yaml  
│   ├── mysql-secrets.yaml  
│   ├── osticket-deployment.yaml  
│   ├── osticket-service.yaml  
│   ├── ingress.yaml  
│   ├── rbac.yaml  
│   └── network-policies.yaml  
├── .github/  
│   └── workflows/  
│       └── deploy.yaml  
└── README.md  

## Getting Started  
***Step 1: Clone the Repo***  
```bash
$ git clone https://github.com/YOUR_USERNAME/osticket-eks.git  
$ cd osticket-eks  
```

***Step 2: Build and Test Containers Locally***     
```bash
$ cd docker  
```
##

## Build the osTicket image
```bash
docker build -t osticket:local .  
```

## Run it to verify it loads
```bash
$ docker run -d -p 8080:80 --name osticket-test osticket:local
```  

Visit http://localhost:8080 in your browser.  
You should see the osTicket setup page.  

## Clean up the test container
```bash
$ docker stop osticket-test && docker rm osticket-test
$ cd ..
```

***Step 3: Deploy Infrastructure with Terraform***  
```bash
$ cd terraform
$ terraform init
$ terraform plan
$ terraform apply
```

This creates the VPC, EKS cluster, and ECR repositories. Takes approximately 15-20 minutes.  
Note the outputs — you will need the ECR repository URLs for the next step.  

***Step 4: Authenticate Docker to ECR***  
Replace <ACCOUNT_ID> with your AWS account number (found in the Terraform outputs or by running aws sts get-caller-identity).  
```bash
$ aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```  

***Step 5: Build, Tag, and Push Images to ECR***  
```bash
# osTicket image
$ docker build -t osticket:v1 -f docker/Dockerfile docker/
$ docker tag osticket:v1 <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket:v1
$ docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket:v1

# MySQL image
$ docker build -t osticket-mysql:v1 -f docker/Dockerfile.mysql docker/
$ docker tag osticket-mysql:v1 <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket-mysql:v1
$ docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket-mysql:v1
```

***Step 6: Connect to the EKS Cluster***  
```bash
$ aws eks update-kubeconfig --name osticket-cluster --region us-east-1
$ kubectl get nodes
```

You should see 2 nodes in Ready status.  

***Step 7: Update Kubernetes Manifests with Your Account ID***  
Before applying, replace <ACCOUNT_ID> in these files with your actual AWS account number:  
- kubernetes/mysql-deployment.yaml  
- kubernetes/osticket-deployment.yaml  

***Step 8: Deploy the Application***  
Apply manifests in this order (order matters — namespaces first, then secrets, then deployments that reference them):  
```bash
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/mysql-secrets.yaml
kubectl apply -f kubernetes/mysql-deployment.yaml
kubectl apply -f kubernetes/mysql-service.yaml
kubectl apply -f kubernetes/osticket-deployment.yaml
kubectl apply -f kubernetes/osticket-service.yaml
kubectl apply -f kubernetes/rbac.yaml
kubectl apply -f kubernetes/network-policies.yaml
```

***Step 9: Verify the Deployment***  
```bash
# Check all pods are running
kubectl get pods -n osticket
kubectl get pods -n database

# Get the LoadBalancer URL
kubectl get svc osticket -n osticket
# Copy the EXTERNAL-IP and visit it in your browser

# Verify network policies exist
kubectl get networkpolicies -n osticket
kubectl get networkpolicies -n database

# Test RBAC permissions
kubectl auth can-i get pods --namespace osticket --as developer        # expected: yes
kubectl auth can-i delete pods --namespace osticket --as developer     # expected: no
kubectl auth can-i get pods --namespace database --as developer        # expected: no

# Check ECR scan results
aws ecr describe-image-scan-findings --repository-name osticket --image-id imageTag=v1
```  

## Teardown
Always delete Kubernetes resources before destroying infrastructure. If you destroy the EKS cluster first, orphaned AWS resources (like the load balancer) will be left in your account.  
```bash
# Delete Kubernetes resources
kubectl delete -f kubernetes/

# Destroy infrastructure
cd terraform
terraform destroy
```

## Production Improvements  
If taking this to production, consider:  

- Secrets Management — Replace native K8s secrets with AWS Secrets Manager + External Secrets Operator
- TLS/HTTPS — Add cert-manager and an Ingress controller with TLS termination
- Monitoring — Add CloudWatch Container Insights or Prometheus/Grafana
- Pod Security Standards — Enforce restricted pod security standards to prevent privileged containers
- Private Cluster Endpoint — Set cluster_endpoint_public_access = false and access via VPN
- Multi-AZ NAT Gateways — One NAT gateway per AZ for high availability
- Image Signing — Use AWS Signer or Cosign to verify image provenance before deployment
- Audit Logging — Enable EKS control plane logging to CloudWatch

## Mission Accomplished!
