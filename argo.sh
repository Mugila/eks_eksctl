#!/usr/bin/env bash

CLUSTER_REGION="us-east-1"
export CLUSTER_ACCOUNT=$(aws sts get-caller-identity --query Account --o text)
export CLUSTER_NAME=$(aws eks list-clusters --query clusters --output text | tr '\t' '\n' | grep 'poc')
INGRESS_HOST="argocd.aadhavan.us"

VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${CLUSTER_REGION} --query cluster.resourcesVpcConfig.vpcId --output text)

# 1. set kube kubeconfig
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${CLUSTER_REGION}
echo -e "\n"

# 2. Create name space for Argo CD
ns_argocd=`kubectl get ns -o json | jq -r '.items[] | .metadata.name' | grep argocd`
if [ -z "$ns_argocd" ]; then
  kubectl create namespace argocd
else
  echo -e "Namespace of argocd already exists\n"
fi

svc_argocd=`kubectl get svc -n argocd -o json | jq -r '.items[] | .metadata.name' | grep argocd-applicationset-controller`
if [ -z "$svc_argocd" ]; then
  echo -e "Start to apply ArgoCD manifest.\n"
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo -e "\nApplying ArgoCD manifest"
  count=0
  while [ -z "$svc_argocd" ]; do
    count=`expr $count + 1`
    if [ $count -gt 10 ]; then
      echo -e "Timed out to apply ArgoCD manifest\n"
      break
    fi

    echo -n "."
    sleep 1
    svc_argocd=`kubectl get svc -n argocd -o json | jq -r '.items[] | .metadata.name' | grep argocd-applicationset-controller`
  done
  echo -e "\nSuccessfully applied ArgoCD manifest\n"
  # kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
   kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "ClusterIP"}}'
  echo -e "Successfully changed ArgoCD server to LoadBalancer type\n"
else
  echo -e "ArgoCD manifest has already been applied\n"
fi

echo "Creating Ingress configuration file: ingress-values.yaml"
cat <<EOF > ingress-values.yaml
# ingress-values.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
    - host: $INGRESS_HOST
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

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
initial_password=`kubectl -n argocd get secret/argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d; echo`
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
    initial_password=`kubectl -n argocd get secret/argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d; echo`
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
  kubectl --namespace argocd delete secret/argocd-initial-admin-secret
  echo -e "\n"
else
  :
fi

# 9. Argo CD
echo "*********************************************************************************************"
echo "External IP      : $external_ip"
echo "Initial User     : $initial_user"
echo "Initial Password : $initial_password"
echo "New Password     : $new_password"
echo "*********************************************************************************************"
echo -e "\n"

# 10. アプリケーションをデプロイする
kubectl apply -f ./your_application.yaml