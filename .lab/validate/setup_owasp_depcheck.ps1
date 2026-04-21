# setup_owasp_depcheck.ps1
# -----------------------
# Helper script to install/setup OWASP Dependency Check on Windows.
# Run as Administrator for system-wide installation.

param(
    [string]$DepCheckVersion = "8.4.2",
    [string]$InstallPath = "C:\tools\owasp-depcheck"
)

$ErrorActionPreference = "Stop"

Write-Host "=== OWASP Dependency Check Setup (Windows) ===" -ForegroundColor Cyan
Write-Host "Version: $DepCheckVersion" -ForegroundColor Gray
Write-Host "Install Path: $InstallPath" -ForegroundColor Gray
Write-Host ""

# Check if already installed
$depcheckCmd = Get-Command dependency-check.bat -ErrorAction SilentlyContinue
if ($depcheckCmd) {
    Write-Host "✓ Dependency Check already installed" -ForegroundColor Green
    & "$($depcheckCmd.Source)" --version 2>$null
    Write-Host ""
    Write-Host "To update database:" -ForegroundColor Yellow
    Write-Host "  dependency-check.bat --updateonly" -ForegroundColor Gray
    exit 0
}

# Check Java availability
$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCmd) {
    Write-Host "ERROR: Java 8 or higher required but not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install Java:" -ForegroundColor Yellow
    Write-Host "  Option 1: Download from https://www.oracle.com/java/technologies/downloads/" -ForegroundColor Gray
    Write-Host "  Option 2: Use Chocolatey: choco install openjdk11" -ForegroundColor Gray
    Write-Host "  Option 3: Use Windows Package Manager: winget install Oracle.JDK.21" -ForegroundColor Gray
    exit 1
}

# Get Java version
$javaVersion = & java -version 2>&1 | Select-String "version" | ForEach-Object { $_ -match 'version "(.+)"' | Out-Null; $matches[1] }
Write-Host "✓ Java found (version $javaVersion)" -ForegroundColor Green

# Create install directory
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "Created directory: $InstallPath" -ForegroundColor Gray
}

# Download
$downloadUrl = "https://github.com/jeremylong/DependencyCheck_Doc/releases/download/v$DepCheckVersion/dependency-check-$DepCheckVersion-win.zip"
$zipPath = Join-Path $InstallPath "depcheck.zip"

Write-Host ""
Write-Host "Downloading Dependency Check $DepCheckVersion..." -ForegroundColor Cyan
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "✓ Download complete" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to download. Check internet connection and version." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Gray
    exit 1
}

# Extract
Write-Host "Extracting..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $zipPath -DestinationPath $InstallPath -Force
    Remove-Item $zipPath
    Write-Host "✓ Extraction complete" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to extract." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Gray
    exit 1
}

# Find dependency-check directory
$depcheckDir = Get-ChildItem $InstallPath -Directory | Where-Object { $_.Name -like "dependency-check*" } | Select-Object -First 1
if (-not $depcheckDir) {
    Write-Host "ERROR: Could not find dependency-check directory after extraction." -ForegroundColor Red
    exit 1
}

$depcheckBinPath = Join-Path $depcheckDir.FullName "bin"
$depcheckBat = Join-Path $depcheckBinPath "dependency-check.bat"

if (-not (Test-Path $depcheckBat)) {
    Write-Host "ERROR: dependency-check.bat not found at $depcheckBat" -ForegroundColor Red
    exit 1
}

# Add to PATH (current session)
$env:Path += ";$depcheckBinPath"
Write-Host "✓ Added to PATH for current session" -ForegroundColor Green

# Option to add to system PATH (requires admin)
if ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains "S-1-5-32-544") {
    Write-Host ""
    Write-Host "Running as Administrator - adding to system PATH..." -ForegroundColor Cyan
    
    [Environment]::SetEnvironmentVariable(
        "PATH",
        "$([Environment]::GetEnvironmentVariable("PATH", "Machine"));$depcheckBinPath",
        "Machine"
    )
    Write-Host "✓ Added to system PATH" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "NOTE: Not running as Administrator." -ForegroundColor Yellow
    Write-Host "To add permanently to system PATH, run this script as Administrator." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Or add manually:" -ForegroundColor Yellow
    Write-Host "  1. Open System Properties (Win+Pause, Advanced tab)" -ForegroundColor Gray
    Write-Host "  2. Environment Variables -> Edit PATH" -ForegroundColor Gray
    Write-Host "  3. Add: $depcheckBinPath" -ForegroundColor Gray
}

# Verify
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Cyan
& $depcheckBat --version
Write-Host "✓ Installation verified" -ForegroundColor Green

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "First run will download NVD database (~1GB, 5-15 minutes):" -ForegroundColor Yellow
Write-Host "  dependency-check.bat --updateonly" -ForegroundColor Gray
Write-Host ""
Write-Host "To run lab validation:" -ForegroundColor Yellow
Write-Host "  .\.lab\validate\06_validate_sca_owasp_depcheck.sh" -ForegroundColor Gray
Write-Host ""
Write-Host "Using this script from PowerShell:" -ForegroundColor Yellow
Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
Write-Host "  .\setup_owasp_depcheck.ps1" -ForegroundColor Gray
