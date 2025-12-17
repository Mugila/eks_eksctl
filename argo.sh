#!/bin/bash
set -x
CLUSTER_REGION="us-east-1"
ARGOCD_NAMESPACE="argocd"
export AWS_ROUTE53_DOMAIN="aadhavan.us"
export CLUSTER_ACCOUNT=$(aws sts get-caller-identity --query Account --o text)
export CLUSTER_NAME=$(aws eks list-clusters --query clusters --output text | tr '\t' '\n' | grep 'poc')
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "${AWS_ROUTE53_DOMAIN}." --query 'HostedZones[0].Id' --o text | awk -F "/" {'print $NF'})
INGRESS_HOST="argo.aadhavan.us"

VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${CLUSTER_REGION} --query cluster.resourcesVpcConfig.vpcId --output text)

# 1. set kube kubeconfig
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${CLUSTER_REGION}
echo -e "\n"



# 2. Create the Argo CD namespace
echo "Creating Kubernetes namespace: $ARGOCD_NAMESPACE"
ns_argocd=`kubectl get ns -o json | jq -r '.items[] | .metadata.name' | grep argocd`
if [ -z "$ns_argocd" ]; then
  kubectl create namespace $ARGOCD_NAMESPACE
else
  echo -e "Namespace of argocd already exists\n"
fi
#kubectl create namespace $ARGOCD_NAMESPACE || echo "Namespace $ARGOCD_NAMESPACE already exists"

# 3. Add the Argo CD Helm repository
echo "Adding Argo CD Helm repository"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

echo "Starting Argo CD installation and ALB exposure process..."
# 4. Install Argo CD using Helm
# We use the default values for the service, which is a ClusterIP,
# and will expose it using an Ingress resource later.
echo "Deploying Argo CD using Helm with custom value file for non HA deployment"
helm install argocd argo/argo-cd --namespace $ARGOCD_NAMESPACE --version 4.8.0 --values argo-non-ha.yaml --wait  --debug
sleep 30
echo "Applying Ingress configuration to expose Argo CD via ALB"
kubectl apply -f argo-ingress.yaml 
sleep 5
kubectl get ingress -n  $ARGOCD_NAMESPACE
echo "Ingress resource created. The AWS ALB is being provisioned..."
echo "It may take a few minutes for the ALB to become active."

# 6. Retrieve the ALB hostname
echo "Waiting for Ingress hostname..."
# Loop until the ingress hostname is available
while [ -z "$ALB_HOSTNAME" ]; do
    ALB_HOSTNAME=$(kubectl get ingress argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    [ -z "$ALB_HOSTNAME" ] && sleep 20
done

echo "AWS ALB Hostname: $ALB_HOSTNAME"

sleep 120 


#CHECK IF ALB hostname is updated in Route 53
# Fetch the Route 53 record's alias target DNS name
echo "Fetching Route 53 record alias target..."
R53_TARGET_DNS_NAME=$(aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --query "ResourceRecordSets[?Name == '${INGRESS_HOST}.' && Type == 'A'].AliasTarget.DNSName" --output text )

if [ -z "$R53_TARGET_DNS_NAME" ]; then
    echo "Error: Could not retrieve Route 53 record target. Check Hosted Zone ID and Record Name."
    exit 1
fi

# Route 53 AliasTargets include a trailing dot, while ALB DNSNames do not. 
# We need to remove the trailing dot from the Route 53 output for a direct comparison.
#R53_TARGET_DNS_NAME_CLEANED=$(echo "$R53_TARGET_DNS_NAME" | sed 's/\.$//')
#echo "Route 53 Target DNS Name: $R53_TARGET_DNS_NAME_CLEANED"

# Compare the two names
if [[ "$ALB_HOSTNAME" -eq "$R53_TARGET_DNS_NAME" ]]; then
    echo "Success: The ALB hostname and Route 53 record alias target match."
    exit 0
else
    echo "Failure: The ALB hostname and Route 53 record alias target DO NOT match amd argocd has not updated the ALB dns in route 53."
    exit 1
fi

echo "The load balancer will take some time to provision. Use this command to wait until Argo CD responds"
curl --head -X GET --retry 20 --retry-all-errors --retry-delay 15 \
  --connect-timeout 5 --max-time 10 -k \
  http://$ALB_HOSTNAME



## 7. Get the initial admin password
#echo "Retrieving initial admin password"
#ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)


# 3. Grep Argo CD external IP 
external_ip=`kubectl get svc argocd-server -n argocd -o json 2>/dev/null | jq -r '.status.loadBalancer.ingress[].hostname' 2>/dev/null`
if [[ -z $external_ip ]]; then
  echo -e "\nWaiting to start argocd-server"
  count=0
  while [[ -z $external_ip ]]; do
    count=`expr $count + 1`
    if [ $count -gt 10 ]; then
      echo -e "Timed out waiting for argocd-server to start"
      break
    fi

    echo -n "."
    sleep 1
    external_ip=`kubectl get svc argocd-server -n argocd -o json 2>/dev/null | jq -r '.status.loadBalancer.ingress[].hostname' 2>/dev/null`
  done
fi
echo -e "\n"

# 4. Argo CD admin user
initial_user="admin"

# 5. Grep inittial password
initial_password=`kubectl -n $ARGOCD_NAMESPACE get secret/argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d; echo`
if [[ -z $initial_password ]]; then
  echo -e "\nWaiting to start secret/argocd-initial-admin-secret"
  count=0
  while [[ -z $initial_password ]]; do
    count=`expr $count + 1`
    if [ $count -gt 20 ]; then
      echo -e "Timed out waiting for secret/argocd-initial-admin-secret to start"
      break
    fi

    echo -n "."
    sleep 1
    initial_password=`kubectl -n $ARGOCD_NAMESPACE get secret/argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d; echo`
  done
fi

# 6. check wheather we are able to login Argo cd
if [ -n "$initial_password" ]; then
  echo -e "\nLogin to Argo CD" 
  accessable_to_argocd=`nslookup -type=ns $external_ip | grep "Authoritative answers can be found from"`
  count=0
  while [ -z "$accessable_to_argocd" ]; do
    count=`expr $count + 1`
    if [ $count -gt 90 ]; then
      echo -e "Timed out to login to Argo CD"
      break
    fi

    echo -n "."
    sleep 1
    accessable_to_argocd=`nslookup -type=ns $external_ip | grep "Authoritative answers can be found from"`
  done
  argocd login "$external_ip" --username admin --password "$initial_password" --insecure

  # 7. change admin password
  new_password=`openssl rand -base64 6`
  echo -e "\nChange your login password to $new_password"
  argocd account update-password --account admin --current-password "$initial_password" --new-password "$new_password" --insecure
  echo -e "\n"

  # 8. Delete  initial admin Secret
  kubectl --namespace $ARGOCD_NAMESPACE delete secret/argocd-initial-admin-secret
  echo -e "\n"
else
  :
fi

# 9. Argo CD
echo "*********************************************************************************************"
echo "Argo CD is ready!"
echo "Argo CD URL: http://$ALB_HOSTNAME"
echo "External IP      : $external_ip"
echo "Initial User     : $initial_user"
echo "Initial Password : $initial_password"
echo "New Password     : $new_password"
echo "*********************************************************************************************"
echo -e "\n"

