# =============================================================================
#  scripts/setup-minikube.ps1
#  Creates and configures both Minikube clusters
#  Run ONE cluster at a time to avoid RAM exhaustion.
# =============================================================================

param(
    [ValidateSet("private-cloud","public-cloud","both")]
    [string]$Cluster = "private-cloud"
)

function Start-Cluster {
    param([string]$Name, [int]$CPUs = 2, [string]$Memory = "2200mb")

    Write-Host ""
    Write-Host "Starting cluster: $Name" -ForegroundColor Cyan
    minikube start `
        --profile      $Name `
        --driver       docker `
        --cpus         $CPUs `
        --memory       $Memory `
        --addons       metrics-server

    Write-Host "Enabling metrics-server addon..." -ForegroundColor Gray
    minikube addons enable metrics-server -p $Name

    Write-Host "Cluster '$Name' is ready." -ForegroundColor Green
}

if ($Cluster -eq "both") {
    Write-Host "WARNING: Starting both clusters may use a lot of RAM." -ForegroundColor Yellow
    Write-Host "Recommended to start one at a time." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/n)"
    if ($confirm -ne "y") { exit 0 }
    Start-Cluster -Name "private-cloud"
    Start-Cluster -Name "public-cloud"
} else {
    Start-Cluster -Name $Cluster
}

Write-Host ""
Write-Host "Current kubectl contexts:" -ForegroundColor Cyan
kubectl config get-contexts
