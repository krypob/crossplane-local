# setup.ps1 — one-command Crossplane local environment setup (Windows)
#
# Usage (PowerShell as Administrator):
#   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#   .\setup.ps1
#
# Optional overrides via environment variables:
#   $env:CLUSTER_NAME = "my-cluster"
#   $env:SKIP_CHECKS  = "1"
#   $env:CROSSPLANE_CHART_VERSION = "1.17.0"
#   .\setup.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Version pins ───────────────────────────────────────────────────────────────
$KindVersion       = if ($env:KIND_VERSION)       { $env:KIND_VERSION }       else { "v0.25.0" }
$KubectlVersion    = if ($env:KUBECTL_VERSION)    { $env:KUBECTL_VERSION }    else { "v1.31.0" }
$HelmVersion       = if ($env:HELM_VERSION)       { $env:HELM_VERSION }       else { "v3.16.2" }
$ClusterName       = if ($env:CLUSTER_NAME)       { $env:CLUSTER_NAME }       else { "crossplane-local" }
$CrossplaneNS      = if ($env:CROSSPLANE_NS)      { $env:CROSSPLANE_NS }      else { "crossplane-system" }
$CrossplaneVersion = if ($env:CROSSPLANE_CHART_VERSION) { $env:CROSSPLANE_CHART_VERSION } else { "" }
$SkipChecks        = $env:SKIP_CHECKS -eq "1"

# ── Minimum requirements ───────────────────────────────────────────────────────
$MIN_RAM_GB  = 8
$REC_RAM_GB  = 16
$MIN_CPU     = 4
$MIN_DISK_GB = 20
$REC_DISK_GB = 40

# ── Color helpers ──────────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "[INFO]  $msg"  -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]    $msg"  -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg"  -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg"  -ForegroundColor Red }
function Write-Section { param($msg) Write-Host "`n══════════════════════════════════════════" -ForegroundColor Cyan
                                     Write-Host "  $msg" -ForegroundColor Cyan
                                     Write-Host "══════════════════════════════════════════`n" -ForegroundColor Cyan }

function Ask-YesNo {
  param([string]$Prompt, [bool]$Default = $true)
  $opts = if ($Default) { "[Y/n]" } else { "[y/N]" }
  while ($true) {
    $ans = Read-Host "$Prompt $opts"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    switch ($ans.ToLower()) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-Host "Please answer y or n." }
    }
  }
}

function Command-Exists { param($cmd) return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# ── Banner ─────────────────────────────────────────────────────────────────────
Write-Host @"
   ____                                  _
  / ___|_ __ ___  ___ ___ _ __ ___  ___| | __ _ _ __   ___
 | |   | '__/ _ \/ __/ __| '_ ` _ \/ __| |/ _` | '_ \ / _ \
 | |___| | | (_) \__ \__ \ |_) | | | (__| | (_| | | | |  __/
  \____|_|  \___/|___/___/ .__/|_|_|\___|_|\__,_|_| |_|\___|
                          |_|
         Local Environment Setup — powered by kind + helm (Windows)
"@ -ForegroundColor Cyan

# ── Step 1 — OS confirmation ───────────────────────────────────────────────────
Write-Section "Step 1 — Operating System"
Write-Host "  Detected: Windows`n"
Write-Host "  Please confirm:"
Write-Host "    1) Windows (Docker Desktop + WSL 2)"
Write-Host "    2) I am inside WSL 2 — please use setup.sh instead`n"

do {
  $osChoice = Read-Host "  Enter choice [1-2]"
} while ($osChoice -notin @("1","2"))

if ($osChoice -eq "2") {
  Write-Warn "Please run setup.sh from your WSL 2 terminal instead."
  exit 0
}

# ── Step 2 — Show requirements ─────────────────────────────────────────────────
Write-Section "Step 2 — Minimum Requirements"
Write-Host "  The following resources are needed to run Crossplane locally:`n"
Write-Host ("  {0,-22} {1,-15} {2,-15}" -f "Resource","Minimum","Recommended")
Write-Host ("  {0,-22} {1,-15} {2,-15}" -f "--------","-------","-----------")
Write-Host ("  {0,-22} {1,-15} {2,-15}" -f "RAM",         "${MIN_RAM_GB} GiB",  "${REC_RAM_GB} GiB")
Write-Host ("  {0,-22} {1,-15} {2,-15}" -f "CPU cores",   "$MIN_CPU",           "6+")
Write-Host ("  {0,-22} {1,-15} {2,-15}" -f "Free disk",   "${MIN_DISK_GB} GiB", "${REC_DISK_GB} GiB")
Write-Host ""
Write-Host "  Required software:`n"
Write-Host "    * Docker Desktop (WSL 2 backend enabled)"
Write-Host "    * WSL 2 with a Linux distro (Ubuntu recommended)"
Write-Host "    * kind    — Kubernetes in Docker"
Write-Host "    * kubectl — Kubernetes CLI"
Write-Host "    * helm    — Kubernetes package manager"
Write-Host "    * up      — Crossplane CLI"
Write-Host ""
Write-Host "  Windows notes:" -ForegroundColor Yellow
Write-Host "    * Docker Desktop -> Settings -> Resources -> Memory >= ${MIN_RAM_GB} GiB"
Write-Host "    * Docker Desktop -> Settings -> General -> Use WSL 2 based engine: ON"
Write-Host "    * Chocolatey (choco) or winget used for package installation`n"

if (!(Ask-YesNo "Do you meet the requirements above and want to continue?")) {
  Write-Warn "Setup cancelled."
  exit 0
}

# ── Step 3 — Check system resources ───────────────────────────────────────────
if (!$SkipChecks) {
  Write-Section "Step 3 — System Resource Checks"
  $allOk = $true

  # RAM
  $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
  if ($ramGB -ge $REC_RAM_GB)  { Write-Ok  "RAM: ${ramGB} GiB" }
  elseif ($ramGB -ge $MIN_RAM_GB) { Write-Warn "RAM: ${ramGB} GiB — meets minimum, recommended ${REC_RAM_GB} GiB" }
  else { Write-Err "RAM: ${ramGB} GiB — below minimum (${MIN_RAM_GB} GiB required)"; $allOk = $false }

  # CPU
  $cpuCores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
  if ($cpuCores -ge $MIN_CPU) { Write-Ok "CPU: $cpuCores logical cores" }
  else { Write-Err "CPU: $cpuCores cores — below minimum ($MIN_CPU required)"; $allOk = $false }

  # Disk
  $drive = (Get-Location).Drive.Name + ":"
  $freeGB = [math]::Round((Get-PSDrive ($drive -replace ":","")).Free / 1GB)
  if ($freeGB -ge $REC_DISK_GB)  { Write-Ok  "Free disk: ${freeGB} GiB" }
  elseif ($freeGB -ge $MIN_DISK_GB) { Write-Warn "Free disk: ${freeGB} GiB — meets minimum, recommended ${REC_DISK_GB} GiB" }
  else { Write-Err "Free disk: ${freeGB} GiB — below minimum (${MIN_DISK_GB} GiB required)"; $allOk = $false }

  # Docker
  if (Command-Exists "docker") {
    try {
      docker info | Out-Null
      $dockerVer = (docker version --format "{{.Server.Version}}" 2>$null)
      Write-Ok "Docker: running ($dockerVer)"
    } catch {
      Write-Err "Docker is installed but not running — start Docker Desktop and retry."
      $allOk = $false
    }
  } else {
    Write-Err "Docker not found — install Docker Desktop: https://www.docker.com/products/docker-desktop"
    $allOk = $false
  }

  Write-Host ""
  if (!$allOk) {
    if (!(Ask-YesNo "Resource checks failed. Continue anyway (not recommended)?" $false)) {
      Write-Warn "Setup cancelled."
      exit 1
    }
  } else {
    Write-Ok "All resource checks passed."
  }
}

# ── Step 4 — Install tools ────────────────────────────────────────────────────
Write-Section "Step 4 — Installing Tools"

function Install-WithWinget {
  param($name, $id)
  if (Command-Exists $name) {
    Write-Ok "$name already installed."
  } else {
    Write-Info "Installing $name via winget ..."
    winget install --id $id --silent --accept-source-agreements --accept-package-agreements
    Write-Ok "$name installed."
  }
}

function Install-WithChoco {
  param($name, $pkg)
  if (Command-Exists $name) {
    Write-Ok "$name already installed."
  } else {
    Write-Info "Installing $name via Chocolatey ..."
    choco install $pkg -y
    Write-Ok "$name installed."
  }
}

# Prefer winget, fall back to choco
if (Command-Exists "winget") {
  Install-WithWinget "kind"    "Kubernetes.kind"
  Install-WithWinget "kubectl" "Kubernetes.kubectl"
  Install-WithWinget "helm"    "Helm.Helm"
} elseif (Command-Exists "choco") {
  Install-WithChoco "kind"    "kind"
  Install-WithChoco "kubectl" "kubernetes-cli"
  Install-WithChoco "helm"    "kubernetes-helm"
} else {
  Write-Warn "Neither winget nor Chocolatey found."
  Write-Host "  Please install tools manually:"
  Write-Host "    kind:    https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
  Write-Host "    kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
  Write-Host "    helm:    https://helm.sh/docs/intro/install/"
  if (!(Ask-YesNo "Continue assuming tools are already installed?")) { exit 1 }
}

# Crossplane CLI (up)
if (Command-Exists "up") {
  Write-Ok "Crossplane CLI (up) already installed."
} else {
  Write-Info "Installing Crossplane CLI (up) ..."
  $upUrl = "https://cli.upbound.io/stable/${UpVersion}/bin/windows_amd64/up.exe"
  $upDest = "$env:LOCALAPPDATA\Programs\up\up.exe"
  New-Item -ItemType Directory -Force -Path (Split-Path $upDest) | Out-Null
  Invoke-WebRequest -Uri $upUrl -OutFile $upDest
  # Add to PATH for this session
  $env:PATH += ";$(Split-Path $upDest)"
  Write-Ok "Crossplane CLI (up) installed to $upDest"
  Write-Warn "Add '$(Split-Path $upDest)' to your system PATH to use 'up' in future sessions."
}

# ── Step 5 — Create kind cluster ───────────────────────────────────────────────
Write-Section "Step 5 — Kubernetes Cluster"

$kindClusters = kind get clusters 2>$null
if ($kindClusters -contains $ClusterName) {
  Write-Warn "kind cluster '$ClusterName' already exists — skipping creation."
  kubectl config use-context "kind-$ClusterName"
} else {
  $kindConfig = Join-Path $PSScriptRoot "configs\kind-config.yaml"
  Write-Info "Creating kind cluster '$ClusterName' ..."
  kind create cluster --name $ClusterName --config $kindConfig --wait 120s
  Write-Ok "Cluster '$ClusterName' created."
  kubectl config use-context "kind-$ClusterName"
  Write-Ok "kubectl context set to kind-$ClusterName."
}

# ── Step 6 — Helm repos & Crossplane ──────────────────────────────────────────
Write-Section "Step 6 — Installing Crossplane"

$repos = helm repo list 2>$null
if ($repos -notmatch "crossplane-stable") {
  Write-Info "Adding crossplane-stable Helm repo ..."
  helm repo add crossplane-stable https://charts.crossplane.io/stable
}
helm repo update

$helmStatus = helm status crossplane -n $CrossplaneNS 2>$null
if ($helmStatus) {
  Write-Warn "Crossplane already installed in '$CrossplaneNS'. Skipping."
} else {
  Write-Info "Creating namespace '$CrossplaneNS' ..."
  kubectl create namespace $CrossplaneNS --dry-run=client -o yaml | kubectl apply -f -

  Write-Info "Installing Crossplane via Helm ..."
  $versionArg = if ($CrossplaneVersion) { @("--version", $CrossplaneVersion) } else { @() }
  helm install crossplane crossplane-stable/crossplane `
    --namespace $CrossplaneNS `
    --set "args={--debug}" `
    --wait `
    --timeout 5m `
    @versionArg
  Write-Ok "Crossplane installed."
}

# ── Step 7 — Verify ────────────────────────────────────────────────────────────
Write-Section "Step 7 — Verifying Installation"

Write-Info "Waiting for Crossplane pods ..."
kubectl wait pod `
  --for=condition=Ready `
  --selector=app=crossplane `
  --namespace=$CrossplaneNS `
  --timeout=120s

Write-Host ""
Write-Info "Pod status:"
kubectl get pods -n $CrossplaneNS

Write-Host ""
Write-Info "CRDs (first 10):"
kubectl get crds | Select-String "crossplane" | Select-Object -First 10

# ── Done ───────────────────────────────────────────────────────────────────────
Write-Section "Setup Complete"
Write-Host "  Your local Crossplane environment is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "  Cluster : $ClusterName"
Write-Host "  Context : kind-$ClusterName"
Write-Host ""
Write-Host "  Quick-start commands:"
Write-Host "    kubectl get pods -n $CrossplaneNS" -ForegroundColor Cyan
Write-Host "    kubectl get crds | Select-String crossplane" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To tear down:"
Write-Host "    kind delete cluster --name $ClusterName" -ForegroundColor Cyan
Write-Host ""
