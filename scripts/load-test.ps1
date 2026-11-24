# =============================================================================
#  scripts/load-test.ps1
#  Windows PowerShell load-testing script for HPA demonstration
#  Usage:  .\scripts\load-test.ps1 -Url "http://192.168.49.2:30000" -Requests 500 -Concurrency 10
# =============================================================================

param(
    [string]$Url         = "http://192.168.49.2:30000",
    [int]   $Requests    = 500,
    [int]   $Concurrency = 10,
    [int]   $DurationSec = 120
)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  HPA Load Test – Visitor Counter" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Target URL  : $Url"
Write-Host "  Requests    : $Requests"
Write-Host "  Concurrency : $Concurrency"
Write-Host "  Duration    : $DurationSec seconds"
Write-Host ""

# ── Record replica count BEFORE load ─────────────────────────────────────
Write-Host "[BEFORE] Replica count:" -ForegroundColor Yellow
kubectl get hpa flask-hpa

$startTime = Get-Date
$endTime   = $startTime.AddSeconds($DurationSec)
$counter   = 0
$errors    = 0

Write-Host ""
Write-Host "Starting load test at $startTime ..." -ForegroundColor Green

# ── Send HTTP requests in a loop ─────────────────────────────────────────
while ((Get-Date) -lt $endTime) {
    $jobs = @()
    for ($i = 0; $i -lt $Concurrency; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($url)
            try {
                $response = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing
                return $response.StatusCode
            } catch {
                return 0
            }
        } -ArgumentList $Url
    }

    # Wait for all concurrent jobs
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job

    foreach ($r in $results) {
        $counter++
        if ($r -ne 200) { $errors++ }
    }

    $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
    Write-Host "  [$elapsed s] Requests sent: $counter  |  Errors: $errors" -ForegroundColor Gray

    # Check replica count every 30 seconds
    if ($counter % ($Concurrency * 15) -eq 0) {
        Write-Host ""
        Write-Host "[DURING] HPA status:" -ForegroundColor Yellow
        kubectl get hpa flask-hpa
        kubectl get pods -l app=flask-visitor-counter
        Write-Host ""
    }
}

Write-Host ""
Write-Host "Load test finished at $(Get-Date)" -ForegroundColor Green
Write-Host "Total requests : $counter"
Write-Host "Total errors   : $errors"
Write-Host ""

# ── Record replica count AFTER load ──────────────────────────────────────
Write-Host "[AFTER] HPA status:" -ForegroundColor Yellow
kubectl get hpa flask-hpa
kubectl get pods -l app=flask-visitor-counter

Write-Host ""
Write-Host "Wait 2 minutes then check again to see scale-down." -ForegroundColor Cyan
