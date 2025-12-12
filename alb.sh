#!/bin/bash
set -x
# https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/values.yaml
#https://github.com/aws/eks-charts
#https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller

# --- Configuration Variables ---
AWS_REGION="us-east-1"
CLUSTER_NAME="eks-poc"
LBC_SERVICE_ACCOUNT_NAME="aws-load-balancer-controller"
LBC_NAMESPACE="kube-system"
VPC_ID="aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text"

echo "Adding the EKS Helm repository..."
# Add the EKS chart repository to Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
echo "Installing the TargetGroupBinding CRDs..."
# Install the necessary Custom Resource Definitions (CRDs)
kubectl apply -k "github.com"

echo "Installing the AWS Load Balancer Controller using Helm..."
# Install the controller via Helm, using the created service account
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n "${LBC_NAMESPACE}" \
    --set clusterName="${CLUSTER_NAME}" \
    --set serviceAccount.create=false \
    --set serviceAccount.name="${LBC_SERVICE_ACCOUNT_NAME}" \
    --set "${VPC_ID}"

echo "Verifying installation..."
# Verify the deployment status
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get crds | grep -iE "elbv2"

echo "AWS Load Balancer Controller installation script finished."