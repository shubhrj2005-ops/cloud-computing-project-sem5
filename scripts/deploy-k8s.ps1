# =============================================================================
#  scripts/deploy-k8s.ps1
#  Deploy the application to the active Minikube cluster
#  Usage: .\scripts\deploy-k8s.ps1 -Profile "private-cloud"
# =============================================================================

param(
    [string]$Profile = "minikube"   # minikube | private-cloud | public-cloud
)

Write-Host ""
Write-Host "Deploying to cluster profile: $Profile" -ForegroundColor Cyan

# ── Switch context ────────────────────────────────────────────────────────
kubectl config use-context $Profile

# ── Load the Docker image into Minikube ───────────────────────────────────
Write-Host "Loading Docker image into Minikube..."
minikube image load visitor-counter:latest -p $Profile

# ── Apply manifests ───────────────────────────────────────────────────────
Write-Host "Applying Redis manifests..."
kubectl apply -f k8s/redis-deployment.yaml

Write-Host "Applying Flask manifests..."
kubectl apply -f k8s/flask-deployment.yaml

Write-Host "Applying HPA..."
kubectl apply -f k8s/hpa.yaml

Write-Host ""
Write-Host "Waiting for pods to be ready (up to 90 seconds)..."
kubectl wait --for=condition=ready pod -l app=flask-visitor-counter --timeout=90s

Write-Host ""
Write-Host "Current pod status:" -ForegroundColor Cyan
kubectl get pods
kubectl get services
kubectl get hpa

Write-Host ""
$ip = minikube ip -p $Profile
Write-Host "Application URL: http://${ip}:30000" -ForegroundColor Green
