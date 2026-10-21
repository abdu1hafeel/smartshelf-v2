<#
.SYNOPSIS
  SmartShelf V2 - Shopkeeper Flutter App Staging Launcher
.DESCRIPTION
  Launches the Flutter shopkeeper application pointing to the SmartShelf V2 Supabase Staging backend.
  Reads the public Supabase anon key dynamically from admin-website/.env.local at runtime.
  Enforces compile-time flags to prevent silent fallback to localhost.
  Never prints or exposes secret keys or tokens.
#>

[CmdletBinding()]
param (
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir
$envLocalPath = Join-Path $projectRoot "admin-website\.env.local"

if (-not (Test-Path $envLocalPath)) {
    Write-Host "[ERROR] Configuration missing: Could not find '$envLocalPath'." -ForegroundColor Red
    Write-Host "Please ensure admin-website/.env.local is configured with VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY." -ForegroundColor Yellow
    exit 1
}

$supabaseUrl = $null
$supabaseAnonKey = $null

Get-Content -Path $envLocalPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -match "^VITE_SUPABASE_URL\s*=\s*(.+)$") {
        $supabaseUrl = $Matches[1].Trim(" `'`"")
    } elseif ($line -match "^VITE_SUPABASE_ANON_KEY\s*=\s*(.+)$") {
        $supabaseAnonKey = $Matches[1].Trim(" `'`"")
    }
}

if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
    Write-Host "[ERROR] VITE_SUPABASE_URL not found in $envLocalPath." -ForegroundColor Red
    exit 1
}

if ($supabaseUrl -match "localhost" -or $supabaseUrl -match "127\.0\.0\.1") {
    Write-Host "[ERROR] Staging launch rejected: VITE_SUPABASE_URL is pointing to localhost ($supabaseUrl)." -ForegroundColor Red
    exit 1
}

if (-not ($supabaseUrl.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase))) {
    Write-Host "[ERROR] Security requirement: Staging Supabase URL must use HTTPS ($supabaseUrl)." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    Write-Host "[ERROR] VITE_SUPABASE_ANON_KEY not found in $envLocalPath." -ForegroundColor Red
    exit 1
}

if ($supabaseAnonKey -match "service_role" -or $supabaseAnonKey -match "secret") {
    Write-Host "[CRITICAL SECURITY ERROR] A service-role or secret key was detected! Aborting launch." -ForegroundColor Red
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  SmartShelf V2 - Shopkeeper Mobile Application (Staging Target)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Backend Target : $supabaseUrl" -ForegroundColor Green
Write-Host "  Environment    : staging (Compile-time enforced)" -ForegroundColor Green
Write-Host "  Public Anon Key: Loaded from admin-website/.env.local ($($supabaseAnonKey.Length) chars, verified non-secret)" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

Push-Location $scriptDir
try {
    $dartDefines = @(
        "--dart-define=ENVIRONMENT=staging",
        "--dart-define=SUPABASE_URL=$supabaseUrl",
        "--dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey"
    )

    $allArgs = @("run") + $dartDefines + $FlutterArgs
    Write-Host "`nExecuting: flutter run --dart-define=ENVIRONMENT=staging --dart-define=SUPABASE_URL=$supabaseUrl --dart-define=SUPABASE_ANON_KEY=*** $FlutterArgs`n" -ForegroundColor Gray
    & flutter @allArgs
} finally {
    Pop-Location
}
