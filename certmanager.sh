#!/bin/bash
set -x
#kubectl config current-context

#aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${CLUSTER_REGION}

#https://cert-manager.io/docs/installation/best-practice/
#AWS_REGION="us-east-1"
#CLUSTER_NAME="eks-poc"
CLUSTER_REGION="us-east-1"
export CLUSTER_ACCOUNT=$(aws sts get-caller-identity --query Account --o text)
export CLUSTER_NAME=$(aws eks list-clusters --query clusters --output text | tr '\t' '\n' | grep 'poc')
LBC_SERVICE_ACCOUNT_NAME="cert-manager"
LBC_NAMESPACE="kube-system"

VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${CLUSTER_NAME} --query cluster.resourcesVpcConfig.vpcId --output text)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${CLUSTER_REGION}

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io --force-update
#helm repo update

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
