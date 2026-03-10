#!/bin/bash
# verify-pdbs.sh

echo "Checking PodDisruptionBudgets..."

kubectl get pdb -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
MIN_AVAILABLE:.spec.minAvailable,\
MAX_UNAVAILABLE:.spec.maxUnavailable,\
ALLOWED_DISRUPTIONS:.status.disruptionsAllowed

# Check for pods without PDBs
echo "Deployments without PodDisruptionBudgets:"
kubectl get deploy -A -o json | jq -r '
  .items[] |
  select(.spec.replicas > 1) |
  "\(.metadata.namespace)/\(.metadata.name)"
' | while read deploy; do
  ns=$(echo $deploy | cut -d/ -f1)
  name=$(echo $deploy | cut -d/ -f2)

  labels=$(kubectl get deploy $name -n $ns -o jsonpath='{.spec.selector.matchLabels}')

  # Check if PDB exists for these labels
  if ! kubectl get pdb -n $ns -o json | jq -e --arg labels "$labels" \
    '.items[] | select(.spec.selector.matchLabels == ($labels | fromjson))' > /dev/null; then
    echo "  WARNING: $deploy has no PDB"
  fi
done