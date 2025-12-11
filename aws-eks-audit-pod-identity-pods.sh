#!/bin/bash

CLUSTER_NAME="$1"

while IFS= read -r pod_identity_assn; do
  association_id=$(jq -r .associationId <<<"${pod_identity_assn}")
  service_account=$(jq -r .serviceAccount <<<"${pod_identity_assn}")
  namespace=$(jq -r .namespace <<<"${pod_identity_assn}")
  association=$(aws eks describe-pod-identity-association --cluster "${CLUSTER_NAME}" --association-id "${association_id}")
  role_arn=$(jq -r '.association.roleArn' <<<"${association}")
  role_name=$(jq -r '.association.roleArn | split("/") | .[1]' <<<"${association}")
  echo "Kubernetes Service Account: system:serviceaccount:${namespace}:${service_account}"
  echo "Role ARN: ${role_arn}"
  echo "Policy Attachments:"
  aws iam list-attached-role-policies --role-name "${role_name}" | jq -r .'AttachedPolicies[].PolicyArn'

  echo ""
done < <(aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" | jq -c '.associations[]')