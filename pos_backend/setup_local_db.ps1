$ErrorActionPreference = 'Stop'

$pgDataDir = 'C:\Program Files\PostgreSQL\16\data'
$pgBin = 'C:\Program Files\PostgreSQL\16\bin'

function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Cyan
}

function Write-Ok($message) {
    Write-Host "[OK] $message" -ForegroundColor Green
}

function Write-Warn($message) {
    Write-Host "[WARN] $message" -ForegroundColor Yellow
}

Write-Info 'Checking PostgreSQL installation...'

if (-not (Test-Path $pgDataDir)) {
    Write-Warn 'PostgreSQL is not installed yet.'

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info 'Installing PostgreSQL via winget...'
        winget install --id PostgreSQL.PostgreSQL --accept-source-agreements --accept-package-agreements
    }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Info 'Installing PostgreSQL via Chocolatey...'
        choco install postgresql --params "/Password:Reihan12" -y
    }
    else {
        Write-Warn 'Neither winget nor choco is available on this machine.'
        Write-Host ''
        Write-Host 'Manual installation:' -ForegroundColor Yellow
        Write-Host '1. Download PostgreSQL installer from https://www.postgresql.org/download/windows/' -ForegroundColor Yellow
        Write-Host '2. Install PostgreSQL with password: Reihan12' -ForegroundColor Yellow
        Write-Host '3. Ensure the bin folder is on PATH.' -ForegroundColor Yellow
        Write-Host '4. Run this script again after installation.' -ForegroundColor Yellow
        exit 1
    }
}

$env:Path = "$pgBin;$env:Path"

Write-Info 'Checking database status...'
$pgReady = & psql --version 2>$null
if (-not $pgReady) {
    Write-Warn 'psql was not found in PATH. Add PostgreSQL bin folder to PATH and retry.'
    exit 1
}

$serviceName = 'postgresql-x64-16'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Warn "Service '$serviceName' does not exist. Starting PostgreSQL may require the installed service to be created manually."
    Write-Host ''
    Write-Host 'Try: pg_ctl -D "C:\Program Files\PostgreSQL\16\data" start' -ForegroundColor Yellow
    exit 1
}

if ($service.Status -ne 'Running') {
    Write-Info "Starting PostgreSQL service '$serviceName'..."
    Start-Service -Name $serviceName
}

Write-Info 'Creating database pos_db if missing...'
$env:PGPASSWORD = 'Reihan12'
$databaseExists = & psql -U postgres -h 127.0.0.1 -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='pos_db';"
if (-not $databaseExists) {
    & createdb -U postgres -h 127.0.0.1 pos_db
}

Write-Ok 'PostgreSQL is ready.'
Write-Host ''
Write-Host 'Next step:' -ForegroundColor Cyan
Write-Host 'cd c:\Users\Reihan\pos_system_project\pos_backend' -ForegroundColor White
Write-Host 'npm install' -ForegroundColor White
Write-Host 'Set ADMIN_BOOTSTRAP_TOKEN to a unique random secret (at least 32 characters) in your local .env before starting the backend.' -ForegroundColor Yellow
Write-Host 'npm start' -ForegroundColor White
Write-Host ''
Write-Host 'On first launch, select Admin and enter the bootstrap token to create the first 6-digit PIN. Do not share the token.' -ForegroundColor White
