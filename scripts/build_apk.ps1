param(
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "debug",
    [string]$EnvFile = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "booth.env")
)

. "$PSScriptRoot\env.ps1"
Import-BoothEnv -EnvFile $EnvFile

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appRoot = Join-Path $repoRoot "app"

$flutterArgs = @(
    "build",
    "apk",
    "--$Mode",
    "--dart-define=BOOTH_BACKEND=$env:BOOTH_BACKEND",
    "--dart-define=BOOTH_WORKFLOW=$env:WORKFLOW"
)

Push-Location $appRoot
try {
    flutter @flutterArgs
}
finally {
    Pop-Location
}
