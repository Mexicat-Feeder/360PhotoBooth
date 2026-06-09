param()

function Import-BoothEnv {
    param(
        [string]$EnvFile = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "booth.env")
    )

    if (-not (Test-Path -LiteralPath $EnvFile)) {
        throw "Env file not found: $EnvFile"
    }

    Get-Content -LiteralPath $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            return
        }
        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($key) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }

    [Environment]::SetEnvironmentVariable("BOOTH_ENV_FILE", $EnvFile, "Process")
}
