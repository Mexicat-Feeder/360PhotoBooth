param(
    [string]$EnvFile = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "booth.env")
)

. "$PSScriptRoot\env.ps1"
Import-BoothEnv -EnvFile $EnvFile

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$bindHost = if ($env:BOOTH_HOST) { $env:BOOTH_HOST } else { "0.0.0.0" }
$port = if ($env:BOOTH_PORT) { $env:BOOTH_PORT } else { "8000" }

Push-Location $repoRoot
try {
    python -m uvicorn booth_backend.server:app --host $bindHost --port $port
}
finally {
    Pop-Location
}
