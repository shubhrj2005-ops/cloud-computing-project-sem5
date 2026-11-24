# =============================================================================
#  scripts/failover-demo.ps1
#  Hybrid Cloud Failover Demonstration
#
#  ⚠️  IMPORTANT: This is a LOCAL SIMULATION using two Minikube clusters.
#      It does NOT represent an actual public cloud deployment.
#      Redis data is NOT synchronised between clusters.
#
#  Prerequisites:
#    - Two Minikube clusters named "private-cloud" and "public-cloud"
#    - Application already deployed to both clusters
#    - Run from an elevated (Administrator) PowerShell window
# =============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Hybrid Cloud Failover Demo (LOCAL SIMULATION)" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "NOTE: This simulates two cloud environments using Minikube." -ForegroundColor Yellow
Write-Host "      This is NOT an actual public/private cloud setup." -ForegroundColor Yellow
Write-Host "      Redis data is NOT replicated between clusters." -ForegroundColor Yellow
Write-Host ""

# ── Step 1: Show both clusters are running ───────────────────────────────
Write-Host "STEP 1: Checking cluster status..." -ForegroundColor Cyan
minikube status -p private-cloud
Write-Host ""
minikube status -p public-cloud
Write-Host ""

# ── Step 2: Show private-cloud is serving traffic ────────────────────────
Write-Host "STEP 2: Private cloud application URL:" -ForegroundColor Cyan
$privateIP = minikube ip -p private-cloud
Write-Host "  Private Cloud URL: http://${privateIP}:30000" -ForegroundColor Green
Write-Host ""

# ── Step 3: Simulate private-cloud failure ────────────────────────────────
Write-Host "STEP 3: Simulating private-cloud failure..." -ForegroundColor Red
Write-Host "  Stopping private-cloud cluster (press Ctrl+C to abort)"
Start-Sleep -Seconds 3
minikube stop -p private-cloud
Write-Host "  private-cloud is now DOWN." -ForegroundColor Red
Write-Host ""

# ── Step 4: Redirect traffic to public-cloud ─────────────────────────────
Write-Host "STEP 4: Switching traffic to public-cloud..." -ForegroundColor Cyan
kubectl config use-context public-cloud
$publicIP = minikube ip -p public-cloud
Write-Host ""
Write-Host "  Public Cloud URL: http://${publicIP}:30001" -ForegroundColor Green
Write-Host ""
Write-Host "  Open this URL in your browser to verify the application" -ForegroundColor Yellow
Write-Host "  is still serving requests from public-cloud." -ForegroundColor Yellow
Write-Host ""

# ── Step 5: Show public-cloud pods are healthy ────────────────────────────
Write-Host "STEP 5: Public cloud pod status:" -ForegroundColor Cyan
kubectl get pods -l app=flask-visitor-counter --context=public-cloud
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Failover simulation complete." -ForegroundColor Green
Write-Host "  To restore private-cloud: minikube start -p private-cloud" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
