#!/bin/bash
set -x
kubectl config current-context
export CLUSTER_ACCOUNT=$(aws sts get-caller-identity --query Account --o text)
export CLUSTER_NAME="eks-poc"
export CLUSTER_REGION="us-east-1"
export AWS_ROUTE53_DOMAIN="aadhavan.us"
export CLUSTER_VPC=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${CLUSTER_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "${AWS_ROUTE53_DOMAIN}." --query 'HostedZones[0].Id' --o text | awk -F "/" {'print $NF'})
aws route53 list-resource-record-sets --hosted-zone-id  ${HOSTED_ZONE_ID}  --query "ResourceRecordSets[?Name == '${AWS_ROUTE53_DOMAIN}.']"
#verify that sa account is already created through eksct cluster creation
kubectl get sa external-dns -n kube-system -o yaml  
#Install the ExternalDNS Add-On
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${CLUSTER_REGION}
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update
#helm upgrade --wait --timeout 900s --install externaldns-release \
helm install  external-dns external-dns/external-dns --namespace kube-system \
  --set provider.name=aws \
  --set aws.zoneType=public \
  --set txtOwnerId="${HOSTED_ZONE_ID}" \
  --set domainFilters\[0\]="${AWS_ROUTE53_DOMAIN}" \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.create=false \
  --set policy=sync 
kubectl logs $(kubectl get pods -A --field-selector=status.phase=Running  | egrep -o 'external-dns[A-Za-z0-9-]+') -n kube-system --tail=2 | egrep -i "All records are already up to date"

 # watch logs continuosly for errors  kubectl logs -f $(kubectl get pods -A --field-selector=status.phase=Running  | egrep -o 'external-dns[A-Za-z0-9-]+') -n kube-system --tail=2 | egrep -i "error"
  # validate the external dns pod status 
  #kubectl describe pods external-dns-5cd67f9577-rbzd7 -n kube-system 
 # oci://registry-1.docker.io/bitnamicharts/external-dns --namespace kube-system
