# --- Configuration Variables ---

#https://cert-manager.io/docs/installation/best-practice/
AWS_REGION="us-east-1"
CLUSTER_NAME="eks-poc"
LBC_SERVICE_ACCOUNT_NAME="cert-manager"
LBC_NAMESPACE="kube-system"

VPC_ID=$(aws eks describe-cluster --name eks-poc --region us-east-1 --query cluster.resourcesVpcConfig.vpcId --output text)

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm install cert-manager jetstack/cert-manager \
--namespace "${LBC_NAMESPACE}" \ # Installs the main components into kube-system
--version v1.19.2 \
--set clusterResourceNamespace=kube-system \ # Tells cert-manager to look for things like DNS provider secrets in kube-system too, matching the main installation namespace. 
--set installCRDs=true


# check certmanager pods in kube-system
kubectl get pods --namespace kube-system -l app.kubernetes.io/name=cert-manager
kubectl get pods --namespace kube-system -l app.kubernetes.io/name=cert-manager-cainjector
kubectl get pods --namespace kube-system -l app.kubernetes.io/name=cert-manager-webhook
