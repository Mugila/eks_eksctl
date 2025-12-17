
#CLUSTER_NAME="eks-poc"
export CLUSTER_NAME=$(aws eks list-clusters --query clusters --output text | tr '\t' '\n' | grep 'poc')
CLUSTER_REGION="us-east-1"
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
helm install external-dns external-dns/external-dns --namespace kube-system \
  --set provider.name=aws \
  --set aws.zoneType=public \
  --set domainFilters\[0\]="${AWS_ROUTE53_DOMAIN}" \
  --set serviceAccount.name=external-dns \
  --set txtOwnerId=external-dns \
  --set serviceAccount.create=false \
  --set policy=sync \
  --wait 

#--set txtOwnerId="${HOSTED_ZONE_ID}" \
sleep 10 
#check logs from ALB controller pods 
for pod in $(kubectl get pods -n kube-system -l app.kubernetes.io/name=external-dns -o jsonpath='{.items[*].metadata.name}'); do
    echo "--- Logs from $pod ---"
    kubectl logs --tail=10 $pod -n kube-system --all-containers=true | grep "All records are already up to date"
done


 # watch logs continuosly for errors  kubectl logs -f $(kubectl get pods -A --field-selector=status.phase=Running  | egrep -o 'external-dns[A-Za-z0-9-]+') -n kube-system --tail=2 | egrep -i "All records are already up to date"
  # validate the external dns pod status 
  #kubectl describe pods external-dns-5cd67f9577-rbzd7 -n kube-system 
 # oci://registry-1.docker.io/bitnamicharts/external-dns --namespace kube-system
