# EKS Kubernetes Secured Container Deployment

> [!IMPORTANT]
> This project containerizes and deploys the osTicket web application to Amazon EKS using Terraform. It implements container image scanning, RBAC with least-privilege roles, Kubernetes network policies enforcing default-deny pod communication, and a CI/CD pipeline with integrated security scanning via Trivy and Checkov.

## Architecture

ECR      — Private container registry with immutable tags, scan-on-push, and KMS encryption.  
EKS      — Managed Kubernetes cluster with 2 worker nodes across 2 AZs.  
VPC      — Public and private subnets; worker nodes in private subnets only.  
CI/CD    — GitHub Actions with OIDC federation, Trivy image scanning, Checkov IaC scanning.  
Security — Namespace isolation, RBAC (developer/db-admin/security-auditor), network policies with default-deny.  

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
git clone https://github.com/YOUR_USERNAME/osticket-eks.git
 
cd osticket-eks  
```

***Step 2: Build and Test Containers Locally***     
```bash
cd docker  
```
##

## Build the osTicket image
```bash
docker build -t osticket:local .  
```

## Run it to verify it loads
```bash
docker run -d -p 8080:80 --name osticket-test osticket:local
```  

Visit http://localhost:8080 in your browser.  
You should see the osTicket setup page.  

## Clean up the test container
```bash
docker stop osticket-test && docker rm osticket-test
cd ..
```

***Step 3: Deploy Infrastructure with Terraform***  
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates the VPC, EKS cluster, and ECR repositories. Takes approximately 15-20 minutes.  
Note the outputs — you will need the ECR repository URLs for the next step.  

***Step 4: Authenticate Docker to ECR***  
Replace <ACCOUNT_ID> with your AWS account number (found in the Terraform outputs or by running aws sts get-caller-identity).  
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```  
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888  
First after using terraform to build the environment, connect my local docker to ECR:
```bash
# osTicket image
docker build -t osticket:v1 -f docker/Dockerfile docker/
docker tag osticket:v1 <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket:v1
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket:v1

# MySQL image
docker build -t osticket-mysql:v1 -f docker/Dockerfile.mysql docker/
docker tag osticket-mysql:v1 <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket-mysql:v1
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/osticket-mysql:v1
```
<img width="1416" height="145" alt="1" src="https://github.com/user-attachments/assets/b16ac1f8-e11e-4738-8473-8417bc37f3ac" />



The ECR has now the 2 repos:
<img width="1367" height="282" alt="2" src="https://github.com/user-attachments/assets/14af7a4a-90db-4d8f-b2be-e51d5cdc1101" />



with the pushed images in them:
<img width="956" height="351" alt="3" src="https://github.com/user-attachments/assets/ce622ff3-b4e0-4e8d-ae47-bcd87cc7cf20" />



when trying to get the nodes via kubectl I got an auth error:
<img width="1754" height="150" alt="4" src="https://github.com/user-attachments/assets/65f25f1c-36ad-407d-a490-59cee1fe119b" />


Strange, let me check who has access to EKS right now:
└─$ aws eks list-access-entries --cluster-name osticket-cluster --region us-east-1 --profile eks
{
    "accessEntries": [
        "arn:aws:iam::<ACCOUNT-ID>:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
        "arn:aws:iam::xxxxxxxxxx:role/default-eks-node-group-20260326053330679800000001",
        "arn:aws:iam::xxxxxxxxxx:role/github-actions-eks-role"
    ]
}
<img width="1040" height="166" alt="5" src="https://github.com/user-attachments/assets/bef5a532-3260-4444-aaa2-2e1f5a59044f" />


Notably missing is my SSO profile.


thats because the sso profile i used to connect to the aws api was fine and was admin, but the eks has a totally different api. so this gave my sso profile that admin access? explain the other roles u said were attachd and y they worked

Yes, your SSO profile has full AWS admin, but EKS Kubernetes API is a completely separate gate. What you just did gave your SSO role a pass through that gate.
The three roles that were already in the access entries:
The EKS service role (aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS) — this is AWS's own internal role. EKS uses it to manage the control plane on your behalf — things like provisioning the API server, managing etcd, handling upgrades. You never interact with this role. AWS creates it automatically and it needs Kubernetes API access to run the cluster internals.
The node group role (default-eks-node-group-20260326...) — this is the IAM role attached to your t3.medium worker nodes. When a node starts up, it needs to register itself with the Kubernetes API server and say "I'm a worker node, send me pods." Without this access entry, the nodes would boot up but the cluster would reject them and they'd never show as Ready. The EKS module created this automatically.
The GitHub Actions role (github-actions-eks-role) — this is the one you defined in iam.tf. It's the role that GitHub Actions assumes through OIDC when running the CI/CD pipeline. It needs Kubernetes API access because the pipeline runs kubectl apply to deploy manifests and kubectl set image to update deployments. You explicitly created this access entry in Terraform.
Each of these roles has a specific job that requires talking to the Kubernetes API. Your SSO role also needs to talk to the Kubernetes API (through kubectl), but nobody added it to the list. The EKS module doesn't know which human identity you'll be using day to day — it only sets up the roles it creates itself. Adding human operator access is your responsibility, which is the step you just completed.


ok i need to add my sso profile to have eks access:
	$ aws eks create-access-entry --cluster-name osticket-cluster --principal-arn arn:aws:iam::xxxxx
 This just creates the entry — it tells EKS "this principal exists and is allowed to authenticate." But at this point the principal has zero permissions inside the cluster. They can knock on the door but can't do anything once inside.
 
 The second command is what actually grants permissions:
	$ aws eks associate-access-policy --principal-arn ... --policy-arn .../AmazonEKSClusterAdminPolicy --access-scope type=cluster
That attaches the admin policy to the entry, which says "this principal can do everything across the entire cluster."
It's a two-step process — create the entry (who), then associate a policy (what they can do). Same pattern as IAM where you create a user first and then attach policies to them.


I open K9s to cehck the setup in the cluster before i apply the kubernetes yaml files (so no pods yet):
<img width="1122" height="338" alt="6" src="https://github.com/user-attachments/assets/956a5d57-4990-4755-9fb2-dd9ad7cedcc3" />


EBS CSI — yes, this is what handles the 10Gi PersistentVolumeClaim for MySQL. When your MySQL deployment asks for persistent storage, the controller pods talk to the AWS API to create an EBS volume, and the node pod on whichever node MySQL lands on mounts that volume into the container.
CoreDNS — no, you didn't specify two replicas in Terraform. You just said most_recent = true. EKS defaults to two CoreDNS replicas because DNS is critical — if DNS goes down, nothing in the cluster can find anything. EKS makes that high availability decision for you.
aws-node — this is not your application pods. These are the VPC CNI plugin pods that manage networking on each node. Every node needs one running so it can assign VPC IP addresses to whatever pods land on that node. Your MySQL pod could land on either node, but whichever node it lands on, the aws-node pod on that node is what gives it an IP address. Think of aws-node as the network plumbing on each machine, not a workload.
kube-proxy — not a load balancer or reverse proxy in the traditional sense. It manages iptables rules on each node. When you create a Kubernetes Service with a ClusterIP, kube-proxy writes network rules on every node that say "if traffic comes in for this ClusterIP, forward it to one of the pods behind the service." So when an osTicket pod on node 1 tries to reach mysql.database.svc.cluster.local, kube-proxy's rules on node 1 intercept that traffic and route it to the MySQL pod wherever it's running. It's more like a distributed routing table than a reverse proxy.

The aws-node is just the nic for k8, and kube-proxy just handles routing.

same to be seen with:
$ kubectl get pods -n kube-system -o wide


Ok now to apply the kubernetes yaml config files:
and after I get everything running!
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
<img width="1114" height="470" alt="7" src="https://github.com/user-attachments/assets/4684e1a5-2d50-40bf-a034-7b712b3e4c69" />

***Step 6: Connect to the EKS Cluster***  
```bash
aws eks update-kubeconfig --name osticket-cluster --region us-east-1
```

All 13 pods running. Get the external URL:
$ kubectl get svc osticket -n osticket
Look for the EXTERNAL-IP column. Paste that into your browser and you should see the osTicket setup page.
<img width="1379" height="81" alt="8" src="https://github.com/user-attachments/assets/4b9ef527-e1c6-4e2a-bb17-4d3e9b8f9b4c" />



I am able to access the containerized osticket install running on K8 now from the browser:
<img width="1162" height="519" alt="9" src="https://github.com/user-attachments/assets/0052ba70-bd9b-4a74-9d7b-645fbadc1105" />



Checkign the policies in K9s shows:
<img width="1231" height="175" alt="10" src="https://github.com/user-attachments/assets/124f515e-2bc3-43f2-b323-bf2b521b7fbd" />


The names are a bit misleading. allow-osticket-ingress doesn't mean osticket allows traffic from itself. It means "allow inbound traffic TO the osticket pods" — specifically from the load balancer on port 80. The allow-mysql-from-osticket means "allow inbound traffic TO mysql, but only FROM the osticket namespace" on port 3306.
The POD-SELECTOR column shows which pods the policy applies to. Where it's blank, the policy applies to all pods in that namespace (the default deny policies use podSelector: {} which means everything). Where it says app=mysql or app=osticket, the policy only targets those specific pods.
For the DNS question — osticket does need DNS and it has it. The default-deny-ingress in the osticket namespace only blocks inbound traffic. It doesn't restrict outbound. Since there's no egress deny policy in the osticket namespace, the osticket pods can freely make outbound connections including DNS lookups and reaching MySQL on port 3306.
The database namespace is different — it has both default-deny-ingress AND default-deny-egress, which blocks everything in both directions. That's why it needs the explicit allow-dns-egress exception. The design choice is intentional: osticket is a web app that needs to reach out to various things, so restricting its egress would be more complex. MySQL should never initiate outbound connections, so locking down egress there is a security hardening step.


I could dive into each policy and see the details with 'd':
 <img width="669" height="298" alt="11" src="https://github.com/user-attachments/assets/c742d651-4d77-4950-9097-a2b4cf1b4497" />


To test the auto recovery of K8 I used ctrl D to delete a pod, and it auto heals instantly:
<img width="1369" height="348" alt="12" src="https://github.com/user-attachments/assets/f0564e4b-7664-45e7-9160-39cb20a5a7ad" />


wow the auto healing for deleting a pod is way faster than from normal console  and using a normal load balancer health check

That's the difference. A traditional ALB health check polls every 30 seconds, detects the failure, waits for the unhealthy threshold (usually 2-3 checks), then drains the target — you're looking at 60-90 seconds minimum before it even reacts. Then you're waiting for autoscaling to spin up a new EC2 instance, boot the OS, install the app, and pass health checks. Could be 3-5 minutes total.

Kubernetes sees the pod die instantly because it's managing the process directly, not polling from outside. The deployment controller notices the replica count dropped below desired, schedules a new pod immediately, and the container starts in seconds because the image is already cached on the node. There's no OS to boot, no instance to provision — it's just starting a process in an existing container runtime.

That's the core value proposition of Kubernetes over traditional EC2 autoscaling. The recovery unit is a lightweight container, not a full virtual machine. That's why companies accept all the Kubernetes complexity — the operational resilience is on a completely different level.



Testing my access control to see if it is configured right shows the correct results:
<img width="821" height="189" alt="13" src="https://github.com/user-attachments/assets/f0654c47-16a9-4c38-a8e6-2ec32b92ca09" />



Now to test access to the mysql pod from inside the osticket namespace, and also outside by spinning up a throw away pod:
<img width="1128" height="201" alt="14" src="https://github.com/user-attachments/assets/aa2af19c-be5e-45c0-8a4a-99ebb376e764" />



Now while having console access in the new test pod I try to access mysql:

That's a success. The "bad header line: 8.0.45" is MySQL responding with its version number (MySQL 8.0.45). wget is complaining because it expects HTTP headers but MySQL is speaking its own protocol. The point is you got a response — the connection went through.


Oops I still got a response.. hmm:
<img width="768" height="126" alt="15" src="https://github.com/user-attachments/assets/88589f55-e597-4d86-ba84-046a49b1f216" />



I checked "what custom configuration has been applied to the VPC CNI addon on this cluster?" The --query "addon.configurationValues" filters the response to show only the configuration
	$ aws eks describe-addon --addon-name vpc-cni --query "addon.configurationValues"
			null
That meant the VPC CNI was running with pure defaults — no custom configuration at all. Since enableNetworkPolicy is off by default and no configuration was set, it wasn't enforcing anything.



I had to enable the policy even though it was there sitting there created, it was not enabled:
$ aws eks update-addon --cluster-name osticket-cluster --addon-name vpc-cni --region us-east-1 --profile eks --configuration-values '{"enableNetworkPolicy": "true"}'
{
    "update": {
        "id": "38c9e7e7-b786-333d-85aa-203b63ecb01f",
        "status": "InProgress",
        "type": "AddonUpdate",
        "params": [
            {
                "type": "ConfigurationValues",
                "value": "{\"enableNetworkPolicy\": \"true\"}"
            }
        ],

That told the VPC CNI addon "start inspecting every packet flowing between pods and check it against the NetworkPolicy rules in the cluster." The CNI pods (the aws-node pods you saw in k9s) picked up that configuration change and started enforcing the policies that were already defined.
Before that command, the aws-node pods were only handling IP assignment for pods. After it, they're also acting as the firewall between pods — checking every connection against the network policies to decide if it's allowed or denied.

Now I see:
<img width="822" height="166" alt="16" src="https://github.com/user-attachments/assets/2ce3e015-0cea-433c-a522-cb04dc8d9daf" />

Showing the network policy is enabled.


Kubernetes lets you create NetworkPolicy objects all day long regardless of whether anything is enforcing them. They just sit there as YAML in the cluster doing nothing. It's like writing firewall rules in a text file but never loading them into iptables.
Network policies require a CNI plugin that supports enforcement. On EKS, the VPC CNI can do it but it's off by default. AWS made it opt-in because enabling it adds processing overhead to every packet flowing between pods — the CNI has to check each connection against the policy rules. For clusters that don't need network policies, that's wasted overhead.
This is actually a common gotcha in the real world. Teams write network policies, see them in kubectl get networkpolicies, assume they're working, and never test. Then during a security audit or pentest someone discovers traffic flows freely between pods that should be blocked. That's exactly what your test just caught.
This is also a great interview talking point — you can explain that you didn't just define the policies, you actually tested enforcement and discovered the CNI needed explicit configuration. That shows real operational depth, not just YAML writing.


Now to try the same test from a pod OUTSIDE of the namespace:
<img width="1493" height="68" alt="17" src="https://github.com/user-attachments/assets/e212a31a-9782-4f74-9f4b-ad20ec27ea2e" />

This was unsuccessful, showing no communication is allowed from outside the osticket namespace.


This test proves your network policies actually block unauthorized traffic and aren't just sitting there doing nothing.
kubectl run test-app --rm -it --namespace osticket --image=busybox -- sh — this creates a temporary throwaway pod in the osticket namespace using busybox (a tiny Linux image with basic tools). --rm means delete the pod automatically when you exit. -it gives you an interactive shell inside the pod. You're now inside a container running in the osticket namespace, as if you were an application living there.
Once you're inside, run wget -qO- --timeout=3 mysql.database.svc.cluster.local:3306. This tries to reach MySQL on port 3306. You should get some garbled output back — that's MySQL's handshake protocol responding. It looks like garbage because wget expects HTTP but MySQL speaks its own protocol. The point is you got a response, meaning the network policy allow-mysql-from-osticket is working — traffic from the osticket namespace is allowed through to MySQL.
Type exit to leave the pod. It gets deleted automatically.
Then run the second test — kubectl run test-default --rm -it --namespace default --image=busybox -- sh. Same thing but now you're in the default namespace, which has no permission to reach MySQL.n
Run the same wget command inside. This time it should hang for 3 seconds and then timeout with no response. The default-deny-ingress policy on the database namespace is blocking the traffic because the default namespace isn't the osticket namespace. MySQL never even sees the request.
Type exit to leave.
The two tests side by side prove that your network policies are selectively allowing traffic based on source namespace — exactly what zero-trust pod communication looks like.
So putting in the osticket namespace is like putting in 'that' folder on the computer, with all the rules that apply in that folder. then testing from outside the folder.
You're stepping inside the folder to see what it can reach, then stepping outside into a different folder and trying the same thing. Same destination, different source, different result — that's the proof the rules work.

In the real world you'd almost never use kubectl run to create pods directly. That's mainly for quick debugging and testing like what you just did.
Production pods are created through deployments — the YAML manifests you wrote. The deployment defines the image, replicas, resource limits, health checks, and labels, and Kubernetes manages the pods from there. If you need a new application pod, you update the deployment (change the replica count, update the image version) and Kubernetes handles creating or replacing pods to match the desired state.
kubectl run creates a bare pod with no deployment managing it. That means no self-healing — if it dies, nothing brings it back. No rolling updates, no replica management, no rollback capability. It's just a one-off container floating in the namespace.
Think of it like this: kubectl run is SSH-ing into a server and manually starting a process. A deployment YAML is defining the process in your infrastructure-as-code so it's reproducible, managed, and survives failures. The first is fine for "let me quickly test something," the second is how you actually run workloads.



To test scalling I run:
$ kubectl scale deployment osticket -n osticket --replicas=4


and get 2 more pods instantly appearing:
<img width="1359" height="179" alt="19" src="https://github.com/user-attachments/assets/7df8207b-86b6-414d-83c8-2c318107216b" />



Now to check the resources of my instances:
First enable metrics in EKS:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

Then:
<img width="1142" height="331" alt="20" src="https://github.com/user-attachments/assets/44f719ab-3c94-4ef4-88ea-6c6570efa324" />


MySQL is using 374 MEM (megabytes) — the heaviest pod in the cluster, which makes sense for a database.
Your two osTicket pods are using 25 and 23 MEM with minimal CPU — lightweight since nobody is hitting the app with traffic.
The ebs-csi controllers are surprisingly resource-hungry at 57 and 63 MEM — that's the storage management overhead.
The %CPU/R and %CPU/L columns show percentage of requests and limits used. They show n/a for the system pods because those don't have resource requests and limits defined. Your osTicket pods would show values there since you set requests and limits in the deployment YAML.
This is the kind of view an engineer uses in production to spot which pods are consuming too many resources, which ones are approaching their limits, and whether nodes have capacity for more workloads.



Now to test if the app breaks inside the pod if K8 remakes it:
kubectl exec opens a shell inside a pod that's already running.
$ kubectl exec -it -n osticket deployment/osticket -- bash

# Inside the pod:
$ service apache2 stop

# Exit and watch — the liveness probe will detect Apache is down
# and Kubernetes will automatically restart the pod
<img width="1294" height="636" alt="21" src="https://github.com/user-attachments/assets/0f331f50-ba1b-4059-b465-54fc02ba763f" />


Seconds later its all healed:
<img width="1193" height="109" alt="23" src="https://github.com/user-attachments/assets/517a0eb4-7ba9-4392-8e61-f48435fcb4f7" />



To test the auto update nature of K8 I edit the yaml of the osticket inside k9s and change the replicas to 4 and instantly i get 2 more pods:

<img width="1317" height="159" alt="24" src="https://github.com/user-attachments/assets/3ae9cefc-3a04-44b7-ae4f-3f695728522d" />



To test the rollback now:
<img width="1003" height="668" alt="25" src="https://github.com/user-attachments/assets/4d6f4dbf-91e0-4da9-9430-b6324e9d24a3" />



Ok and rollback just rolls back to the previous state. Great. Time to teardown.  
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

Lovely project. K8 is boss.

Mission accomplished!
