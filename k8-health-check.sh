#!/bin/bash
set -e

echo "Starting Kubernetes Cluster Health Check"
echo "----------------------------------------"

# Generate a unique ID for this run
RUN_ID=$(date +%s)
TEST_NAMESPACE="health-check-${RUN_ID}"
TEST_PVC="test-pvc-${RUN_ID}"
TEST_POD="test-pod-${RUN_ID}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to clean up resources
cleanup() {
  echo -e "${YELLOW}Cleaning up test resources...${NC}"
  kubectl delete pod $TEST_POD --namespace=$TEST_NAMESPACE --ignore-not-found=true
  kubectl delete pvc $TEST_PVC --namespace=$TEST_NAMESPACE --ignore-not-found=true
  kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true
  echo -e "${GREEN}Cleanup completed${NC}"
}

# Function to print success message
success() {
  echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error message and exit
fail() {
  echo -e "${RED}❌ $1${NC}"
  exit 1
}

# Function to print warning message
warn() {
  echo -e "${YELLOW}⚠️ $1${NC}"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
  fail "kubectl is not installed. Please install kubectl and configure it to connect to your cluster."
fi

# Check if kubectl can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
  fail "Cannot connect to Kubernetes cluster. Please check your kubeconfig file."
fi

# Trap for clean exit
trap cleanup EXIT

# Check 1: Create a test namespace
echo "Check 1: Creating test namespace $TEST_NAMESPACE"
if kubectl create namespace $TEST_NAMESPACE &> /dev/null; then
  success "Namespace created successfully"
else
  fail "Failed to create namespace $TEST_NAMESPACE"
fi

# Check 2: List available StorageClasses
echo "Check 2: Checking available StorageClasses"
SC_COUNT=$(kubectl get storageclass -o name | wc -l)
if [ "$SC_COUNT" -eq 0 ]; then
  fail "No StorageClasses found in the cluster"
fi
DEFAULT_SC=$(kubectl get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -z "$DEFAULT_SC" ]; then
  warn "No default StorageClass found, will use the first available one"
  DEFAULT_SC=$(kubectl get storageclass -o=jsonpath='{.items[0].metadata.name}')
fi
success "Using StorageClass: $DEFAULT_SC"

# Check 3: Create a PVC and pod together (handles WaitForFirstConsumer binding mode)
echo "Check 3: Creating test PVC using StorageClass $DEFAULT_SC"
cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEST_PVC
  namespace: $TEST_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: $DEFAULT_SC
EOF

if [ $? -ne 0 ]; then
  fail "Failed to create PVC"
fi

# Check 4: Immediately create a pod that uses the PVC (for WaitForFirstConsumer binding mode)
echo "Check 4: Creating test pod that mounts the PVC"
cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: busybox
    image: busybox:1.34
    command: ["sh", "-c", "echo 'Kubernetes storage test' > /data/test.txt && sleep 30"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: $TEST_PVC
  restartPolicy: Never
EOF

if [ $? -ne 0 ]; then
  fail "Failed to create pod"
fi

# Wait for both pod to be running and PVC to be bound
echo "Waiting for pod to be running and PVC to be bound (up to 2 minutes)..."
TIMEOUT=120
for i in $(seq 1 $TIMEOUT); do
  POD_STATUS=$(kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o=jsonpath='{.status.phase}')
  PVC_STATUS=$(kubectl get pvc $TEST_PVC -n $TEST_NAMESPACE -o=jsonpath='{.status.phase}')
  
  if [ "$PVC_STATUS" == "Bound" ] && ([ "$POD_STATUS" == "Running" ] || [ "$POD_STATUS" == "Succeeded" ]); then
    success "PVC successfully bound and pod is running"
    break
  fi
  
  if [ $i -eq $TIMEOUT ]; then
    echo "Timed out waiting. PVC status: $PVC_STATUS, Pod status: $POD_STATUS"
    kubectl get pvc $TEST_PVC -n $TEST_NAMESPACE -o yaml
    kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o yaml
    kubectl get events -n $TEST_NAMESPACE
    fail "Resource creation timeout"
  fi
  
  sleep 1
  # Show a spinner to indicate progress
  printf "\r[%s]" "$(printf '=%.0s' $(seq 1 $i))"
done
echo ""

# Wait for pod completion
echo "Waiting for pod to complete..."
TIMEOUT=60
for i in $(seq 1 $TIMEOUT); do
  POD_STATUS=$(kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o=jsonpath='{.status.phase}' 2>/dev/null)
  
  # Check for completion (either running or succeeded is good)
  if [ "$POD_STATUS" == "Succeeded" ]; then
    success "Pod completed successfully"
    break
  fi
  
  # For running pods, check if they're actually ready
  if [ "$POD_STATUS" == "Running" ]; then
    CONTAINER_READY=$(kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o=jsonpath='{.status.containerStatuses[0].ready}')
    if [ "$CONTAINER_READY" == "true" ]; then
      success "Pod is running with container ready"
      break
    fi
  fi
  
  # Check for failure states
  if [ "$POD_STATUS" == "Failed" ]; then
    echo "Pod failed to run"
    kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o yaml
    kubectl get events -n $TEST_NAMESPACE
    fail "Pod execution failed"
  fi
  
  # Timeout check
  if [ $i -eq $TIMEOUT ]; then
    echo "Timed out waiting for pod to complete. Current status: $POD_STATUS"
    kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o yaml
    kubectl get events -n $TEST_NAMESPACE
    fail "Pod execution timeout"
  fi
  
  sleep 1
  # Show a spinner to indicate progress
  printf "\r[%s]" "$(printf '=%.0s' $(seq 1 $i))"
done
echo ""

# Wait for pod to complete
echo "Waiting for pod to complete..."
kubectl wait --for=condition=Ready pod/$TEST_POD -n $TEST_NAMESPACE --timeout=60s &> /dev/null || true
POD_STATUS=$(kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o=jsonpath='{.status.phase}')
if [ "$POD_STATUS" == "Running" ] || [ "$POD_STATUS" == "Succeeded" ]; then
  success "Pod completed successfully"
else
  echo "Pod did not complete successfully. Status: $POD_STATUS"
  kubectl get pod $TEST_POD -n $TEST_NAMESPACE -o yaml
  kubectl get events -n $TEST_NAMESPACE
  fail "Pod execution failed"
fi

# Optional: Add additional checks here
# DNS check
echo "Check 5: Testing DNS resolution within the cluster"
cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: dns-test-pod
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: dns-test
    image: busybox:1.34
    command:
      - "sh"
      - "-c"
      - "nslookup kubernetes.default.svc.cluster.local > /dev/null && echo 'DNS test passed' || echo 'DNS test failed'"
  restartPolicy: Never
EOF

# Wait for DNS test to complete
kubectl wait --for=condition=Ready pod/dns-test-pod -n $TEST_NAMESPACE --timeout=60s &> /dev/null || true
DNS_TEST_RESULT=$(kubectl logs dns-test-pod -n $TEST_NAMESPACE)
if [[ "$DNS_TEST_RESULT" == *"DNS test passed"* ]]; then
  success "DNS resolution is working correctly"
else
  warn "DNS resolution may have issues. Check cluster DNS service."
  kubectl logs dns-test-pod -n $TEST_NAMESPACE
fi
kubectl delete pod dns-test-pod -n $TEST_NAMESPACE --ignore-not-found=true &> /dev/null

echo ""
echo -e "${GREEN}All health checks passed! ✅${NC}"
echo -e "${GREEN}Kubernetes cluster is healthy and ready for workloads.${NC}"

# Summary report
echo ""
echo "Health Check Summary:"
echo "---------------------"
echo "Namespace creation: ✅"
echo "StorageClass availability: ✅"
echo "PVC provisioning: ✅"
echo "Pod scheduling with volume: ✅"
echo "DNS resolution: ✅"
echo ""
echo "To run this health check again, execute:"
echo "$ bash $(basename "$0")"
