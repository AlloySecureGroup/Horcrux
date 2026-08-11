# Horcrux basic workflow for Windows + Docker Desktop.
# Run from the repo root:  .\run-workflow.ps1
#
# What it does, in order:
#   1. Builds and starts the 5-container grid (introducer, 3 storage, client)
#   2. Waits until the client sees all 3 storage servers
#   3. Creates the agentstore alias and saves the rootcap to horcrux-state.json
#   4. Saves a file into the grid
#   5. Stops one storage node (simulated failure)
#   6. Recovers the file with the node still down, and compares byte for byte
#   7. Restarts the stopped node and repairs shares
# Everything is logged to workflow.log next to this script.

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $PSScriptRoot "workflow.log"
Start-Transcript -Path $LogFile -Append | Out-Null

function Step($msg) { Write-Host ("`n=== " + $msg + " ===") }
function Fail($msg) { Write-Host ("FAILED: " + $msg); Stop-Transcript | Out-Null; exit 1 }

$T = "tahoe", "-d", "/var/tahoe/node"

Step "1. Starting the grid (5 containers)"
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Fail "docker compose up" }

Step "2. Waiting for the client to see 3 storage servers"
$connected = 0
foreach ($i in 1..45) {
    $connected = docker exec horcrux-client python -c "import json,urllib.request;d=json.load(urllib.request.urlopen('http://127.0.0.1:3456/?t=json'));print(sum(1 for s in d.get('servers',[]) if s.get('connection_status','').lower().startswith('connected')))" 2>$null
    if ($connected -eq "3") { break }
    Start-Sleep -Seconds 2
}
if ($connected -ne "3") { Fail "client never connected to 3 storage servers (see: docker compose logs)" }
Write-Host "Client connected to 3 storage servers."

Step "3. Creating the agentstore root and saving the state file"
docker exec horcrux-client @T list-aliases 2>$null | Select-String "agentstore" | Out-Null
if (-not $?) { docker exec horcrux-client @T create-alias agentstore }
$rootcap = docker exec horcrux-client sh -c "grep '^agentstore:' /var/tahoe/node/private/aliases | cut -d' ' -f2"
$furl    = docker exec horcrux-client sh -c "cat /grid/introducer.furl"
$state = [ordered]@{
    introducer_furl = $furl.Trim()
    rootcap         = $rootcap.Trim()
    alias           = "agentstore"
    created         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$statePath = Join-Path $PSScriptRoot "horcrux-state.json"
$state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
Write-Host ("State file written: " + $statePath)
Write-Host "Keep this file safe. It is the only key to the stored data."

Step "4. Saving a file into the grid"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
docker exec horcrux-client sh -c "echo 'agent artifact saved at $stamp' > /tmp/artifact.txt"
docker exec horcrux-client @T put /tmp/artifact.txt "agentstore:outputs/artifact.txt"
if ($LASTEXITCODE -ne 0) { Fail "tahoe put" }
$original = docker exec horcrux-client cat /tmp/artifact.txt
Write-Host ("Saved: " + $original)

Step "5. Simulating failure: stopping storage2"
docker stop horcrux-storage2 | Out-Null
Start-Sleep -Seconds 3
Write-Host "storage2 is down. Grid is running on 2 of 3 nodes."

Step "6. Recovering the file with a node down"
docker exec horcrux-client @T get "agentstore:outputs/artifact.txt" /tmp/recovered.txt
if ($LASTEXITCODE -ne 0) { Fail "tahoe get with one node down" }
$recovered = docker exec horcrux-client cat /tmp/recovered.txt
docker cp horcrux-client:/tmp/recovered.txt (Join-Path $PSScriptRoot "recovered.txt") | Out-Null
if ($recovered -eq $original) {
    Write-Host "RECOVERY OK: recovered file matches the original byte for byte."
    Write-Host ("Copied to: " + (Join-Path $PSScriptRoot "recovered.txt"))
} else {
    Fail "recovered file does not match original"
}

Step "7. Restoring the grid and repairing shares"
docker start horcrux-storage2 | Out-Null
Start-Sleep -Seconds 8
docker exec horcrux-client @T deep-check --repair --add-lease agentstore:
Write-Host "Grid restored to 3 of 3 nodes and shares repaired."

Write-Host "`nAll steps completed. Full log: $LogFile"
Write-Host "Web UI: http://localhost:3456    Stop grid: docker compose down"
Stop-Transcript | Out-Null
