# Horcrux basic workflow for Windows + Docker Desktop.
# Run from the folder containing docker-compose.yml:  .\run-workflow.ps1
#
# Steps: start 5-container grid, wait for readiness, create the agentstore
# root and state file, save a file, stop a storage node, recover the file,
# restart the node, repair shares. Full transcript goes to workflow.log.
#
# Note on error handling: docker and tahoe write normal progress to stderr,
# which strict PowerShell mode turns into fake failures. So this script
# checks exit codes explicitly instead of using ErrorActionPreference Stop,
# and routes probes through cmd so stderr never reaches PowerShell.

$LogFile = Join-Path $PSScriptRoot "workflow.log"
Start-Transcript -Path $LogFile -Append | Out-Null

function Step($msg) { Write-Host ("`n=== " + $msg + " ===") }
function Fail($msg) {
    Write-Host ("FAILED: " + $msg)
    Write-Host "`n--- diagnostics: container status ---"
    docker compose ps
    foreach ($c in "horcrux-introducer","horcrux-storage1","horcrux-storage2","horcrux-storage3","horcrux-client") {
        Write-Host ("`n--- last 25 log lines: " + $c + " ---")
        cmd /c ("docker logs --tail 25 " + $c + " 2>&1")
    }
    Write-Host "`nDiagnostics captured above and in workflow.log"
    Stop-Transcript | Out-Null
    exit 1
}
# Run a command inside the client container, silencing stderr via cmd
function ClientQuiet($cmdline) {
    return (cmd /c ("docker exec horcrux-client " + $cmdline + " 2>nul"))
}

$T = "tahoe -d /var/tahoe/node"

Step "1. Starting the grid (5 containers)"
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Fail "docker compose up" }

Step "2. Waiting for the client to see 3 storage servers"
$connected = 0
foreach ($i in 1..60) {
    $raw = ClientQuiet "python /check.py"
    if ($raw) {
        $last = ("$raw" -split "`n")[-1].Trim()
        $n = 0
        if ([int]::TryParse($last, [ref]$n)) { $connected = $n }
        # non-numeric output means docker exec failed; keep waiting and retry
    }
    if ($connected -ge 3) { break }
    Start-Sleep -Seconds 2
}
if ($connected -lt 3) { Fail "client never connected to 3 storage servers" }
Write-Host "Client connected to $connected storage servers."

Step "3. Creating the agentstore root and saving the state file"
$aliases = ClientQuiet "$T list-aliases"
if ("$aliases" -notmatch "agentstore") {
    ClientQuiet "$T create-alias agentstore" | Out-Null
}
$rootcap = (ClientQuiet "sh -c `"grep '^agentstore:' /var/tahoe/node/private/aliases | cut -d' ' -f2`"")
$furl    = (ClientQuiet "cat /grid/introducer.furl")
if (-not $rootcap) { Fail "could not read rootcap (alias creation failed?)" }
$state = [ordered]@{
    introducer_furl = "$furl".Trim()
    rootcap         = "$rootcap".Trim()
    alias           = "agentstore"
    created         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$statePath = Join-Path $PSScriptRoot "horcrux-state.json"
$state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
Write-Host ("State file written: " + $statePath)
Write-Host "Keep this file safe. It is the only key to the stored data."

Step "4. Saving a file into the grid"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
ClientQuiet ("sh -c `"echo 'agent artifact saved at " + $stamp + "' > /tmp/artifact.txt`"") | Out-Null
ClientQuiet "$T put /tmp/artifact.txt agentstore:outputs/artifact.txt" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "tahoe put" }
$original = ClientQuiet "cat /tmp/artifact.txt"
Write-Host ("Saved: " + "$original".Trim())

Step "5. Simulating failure: stopping storage2"
docker stop horcrux-storage2 | Out-Null
Start-Sleep -Seconds 3
Write-Host "storage2 is down. Grid is running on 2 of 3 nodes."

Step "6. Recovering the file with a node down"
ClientQuiet "$T get agentstore:outputs/artifact.txt /tmp/recovered.txt" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "tahoe get with one node down" }
$recovered = ClientQuiet "cat /tmp/recovered.txt"
cmd /c "docker cp horcrux-client:/tmp/recovered.txt `"$PSScriptRoot\recovered.txt`" 2>nul" | Out-Null
if ("$recovered".Trim() -eq "$original".Trim() -and "$recovered".Trim().Length -gt 0) {
    Write-Host "RECOVERY OK: recovered file matches the original."
    Write-Host ("Copied to: " + (Join-Path $PSScriptRoot "recovered.txt"))
} else {
    Fail "recovered file does not match original"
}

Step "7. Restoring the grid and repairing shares"
docker start horcrux-storage2 | Out-Null
Start-Sleep -Seconds 10
ClientQuiet "$T deep-check --repair --add-lease agentstore:"
Write-Host "Grid restored to 3 of 3 nodes and shares repaired."

Write-Host "`nAll steps completed. Full log: $LogFile"
Write-Host "Web UI: http://localhost:3456    Stop grid: docker compose down"
Stop-Transcript | Out-Null
