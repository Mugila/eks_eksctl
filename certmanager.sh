# --- Configuration Variables ---
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
--namespace "${LBC_NAMESPACE}" \
--version v1.19.2 \
--set installCRDs=true