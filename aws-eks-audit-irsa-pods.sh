#!/bin/bash
while IFS= read -r sa_metadata; do
  service_account=$(jq -r .name <<<"${sa_metadata}")
  namespace=$(jq -r .namespace <<<"${sa_metadata}")
  role_arn=$(jq -r .rolearn <<<"${sa_metadata}")
  role_name=$(jq -r '.rolearn | split("/") | .[1]' <<<"${sa_metadata}")

  echo "Service Account: system:serviceaccount:${namespace}:${service_account}"
  echo "Role ARN: ${role_arn}"
  echo "Policy Attachments:"
  aws iam list-attached-role-policies --role-name ${role_name} | jq -r .'AttachedPolicies[].PolicyArn'

  echo ""
done < <(kubectl get serviceaccounts -A -o json | 
  jq -c '.items[] | select(.metadata.annotations."eks.amazonaws.com/role-arn" != null) | 
  {name: .metadata.name, namespace: .metadata.namespace, rolearn: .metadata.annotations."eks.amazonaws.com/role-arn"}'
)