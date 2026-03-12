#!/bin/bash
set -x
# Pre-requisites: Helm, kubectl, and AWS Load Balancer Controller installed.
NAMESPACE="monitoring"
kubectl create namespace $NAMESPACE

# 1. Add Helm Repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

# 2. Deploy Prometheus with Metrics Enabled
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --set prometheus.service.type=ClusterIP \
  --set prometheus.service.annotations."alb\.ingress\.kubernetes\.io/scheme"=internet-facing \
  --set prometheus.service.annotations."alb\.ingress\.kubernetes\.io/target-type"=ip

# 3. Deploy Grafana
#helm install grafana grafana/grafana \
#  --namespace $NAMESPACE \
#  --set service.type=ClusterIP

# 4. Create Shared ALB Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitor-ingress
  namespace: $NAMESPACE
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/group.name: "myapp"
    alb.ingress.kubernetes.io/group.order: '18'
    alb.ingress.kubernetes.io/security-group: sg-06a0beefd0ed45a07
    #alb.ingress.kubernetes.io/inbound-cidrs: 123.10.10.0/24,210.10.20.30/32
    alb.ingress.kubernetes.io/inbound-cidrs: 0.0.0.0/0
    external-dns.alpha.kubernetes.io/hostname: monitoring.aadhavan.us
    #alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/success-codes: "200"
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /grafana
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
          - path: /prometheus
            pathType: Prefix
            backend:
              service:
                name: prometheus-kube-prometheus-prometheus
                port:
                  number: 9090
EOF

echo "Deployment complete. ALB should be created shortly."
echo "Grafana Admin Password: $(kubectl get secret --namespace $NAMESPACE grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"
