# Crossplane Local Environment

One-command setup for a fully functional [Crossplane](https://crossplane.io) local environment.
Choose between a **Standard** stack (Docker + kind) or a **Lightweight** stack (Colima + k3d/k3s).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Stack Comparison](#stack-comparison)
- [Environment Variables](#environment-variables)
- [Project Structure](#project-structure)
- [What Gets Installed](#what-gets-installed)
- [Optional Features](#optional-features)
  - [GUI Dashboard](#gui-dashboard)
  - [Monitoring Stack](#monitoring-stack)
  - [Example Compositions](#example-compositions)
- [Lifecycle Scripts](#lifecycle-scripts)
- [Useful Commands](#useful-commands)
- [Customising the Cluster](#customising-the-cluster)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

> The only thing you must install manually is a container runtime — everything else is installed automatically.

| Stack | Required manually | macOS | Linux | Windows |
|-------|------------------|-------|-------|---------|
| **Standard** | Docker Desktop | [Download](https://www.docker.com/products/docker-desktop) | [Docs](https://docs.docker.com/engine/install/) | [Download](https://www.docker.com/products/docker-desktop) |
| **Lightweight** | Nothing (Colima installed automatically) | via Homebrew | Docker Engine (auto-installed) | — |

---

## System Requirements

### Standard stack (Docker + kind)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 8 GiB | 16 GiB |
| CPU cores | 4 | 6+ |
| Free disk | 20 GiB | 40 GiB |

### Lightweight stack (Colima + k3d/k3s)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 2 GiB | 4 GiB |
| CPU cores | 2 | 4+ |
| Free disk | 8 GiB | 20 GiB |

> Resource checks are **soft** — the script warns if requirements are not met but always lets you continue.

---

## Quick Start

### macOS / Linux

```bash
git clone https://github.com/krypob/crossplane-local.git
cd crossplane-local
chmod +x setup.sh
./setup.sh
```

The script walks you through:

1. **OS selection** — auto-detects macOS / Linux, asks for confirmation
2. **Stack selection** — Standard (Docker + kind) or Lightweight (Colima + k3d)
3. **Requirements display** — shows minimums for the chosen stack
4. **Resource check** — warns on RAM / CPU / disk below minimum (soft, always continuable)
5. **Tool installation** — installs missing tools automatically
6. **Cluster creation** — kind (standard) or k3d/k3s (lightweight)
7. **Crossplane install** — via official Helm chart, waits until pods are ready
8. **GUI prompt** — optional: install Headlamp or Kubernetes Dashboard

### Windows (PowerShell — Administrator)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup.ps1
```

> **WSL 2 users:** run `./setup.sh` from your WSL terminal instead.

---

## Stack Comparison

| | Standard | Lightweight |
|-|----------|-------------|
| Container runtime | Docker Desktop | Colima (macOS) / Docker Engine (Linux) |
| Kubernetes engine | kind (full K8s) | k3d / k3s (certified, ~70% less RAM) |
| Min RAM | 8 GiB | 2 GiB |
| Best for | Existing Docker users, CI parity | Laptops, low-spec machines |
| Cluster config | `configs/kind-config.yaml` | `configs/k3d-config.yaml` |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OS` | auto-detected | `macos` or `linux` — skip OS prompt |
| `STACK` | interactive | `standard` or `lightweight` — skip stack prompt |
| `CLUSTER_NAME` | `crossplane-local` | Name of the cluster |
| `CROSSPLANE_NAMESPACE` | `crossplane-system` | Namespace for Crossplane |
| `CROSSPLANE_CHART_VERSION` | *(latest)* | Pin a specific Helm chart version |
| `KIND_CONFIG_PATH` | `configs/kind-config.yaml` | Custom kind cluster config |
| `K3D_CONFIG_PATH` | `configs/k3d-config.yaml` | Custom k3d cluster config |
| `SKIP_CHECKS` | `0` | `1` = skip resource checks |
| `SKIP_GUI` | `0` | `1` = skip the GUI prompt at the end |
| `COLIMA_CPU` | `2` | CPU cores to allocate to Colima |
| `COLIMA_MEMORY` | `4` | GiB of RAM to allocate to Colima |
| `COLIMA_DISK` | `60` | GiB of disk to allocate to Colima |

```bash
# Examples
OS=macos STACK=lightweight ./setup.sh
CLUSTER_NAME=my-xp CROSSPLANE_CHART_VERSION=2.2.0 ./setup.sh
SKIP_CHECKS=1 SKIP_GUI=1 ./setup.sh
```

---

## Project Structure

```
crossplane-local/
├── setup.sh                      # Entry point — macOS / Linux
├── setup.ps1                     # Entry point — Windows (PowerShell)
├── teardown.sh                   # Stop and remove the local environment
├── update.sh                     # Upgrade Crossplane and providers in-place
├── setup-gui.sh                  # Optional: install Headlamp or Kubernetes Dashboard
├── setup-monitoring.sh           # Optional: install Prometheus + Grafana
│
├── scripts/
│   ├── common.sh                 # Colors, logging, shared helpers
│   ├── requirements.sh           # Display and check system requirements
│   ├── install.sh                # Install tools (kind/k3d, kubectl, helm, k9s, up)
│   └── cluster.sh                # Create cluster, install Crossplane
│
├── configs/
│   ├── kind-config.yaml          # kind cluster layout (1 control-plane + 2 workers)
│   └── k3d-config.yaml           # k3d cluster layout (1 server + 1 agent)
│
└── examples/
    ├── apply.sh                  # Apply all examples
    ├── destroy.sh                # Remove all examples
    ├── 01-provider/
    │   ├── provider-kubernetes.yaml
    │   └── providerconfig-kubernetes.yaml
    ├── 02-compositions/
    │   └── xnamespace/
    │       ├── xrd.yaml          # CompositeResourceDefinition: AppNamespace
    │       └── composition.yaml  # Provisions Namespace + ResourceQuota + LimitRange
    └── 03-claims/
        └── my-app-namespace.yaml # Example claim
```

---

## What Gets Installed

### Core tools (all stacks)

| Tool | Purpose |
|------|---------|
| **kubectl** | Kubernetes CLI |
| **helm** | Installs Crossplane and optional stacks via Helm charts |
| **k9s** | Terminal UI for browsing cluster resources |
| **up** | Crossplane CLI for managing providers and compositions |
| **Crossplane** | Deployed into `crossplane-system` namespace |

### Standard stack only

| Tool | Purpose |
|------|---------|
| **kind** | Runs full Kubernetes inside Docker containers |

### Lightweight stack only

| Tool | Purpose |
|------|---------|
| **Colima** | Lightweight container runtime (macOS) — replaces Docker Desktop |
| **k3d** | Runs k3s (lightweight certified Kubernetes) inside containers |

---

## Optional Features

### GUI Dashboard

```bash
./setup-gui.sh
```

Choose between:

| Option | Access | Notes |
|--------|--------|-------|
| **Headlamp** | `http://localhost:4466` | Open-source K8s UI, installed locally via Helm, has a Crossplane plugin |
| **Kubernetes Dashboard** | `https://localhost:8443` | Official Kubernetes web UI, open-source, no account required, installed via Helm |

> Also prompted automatically at the end of `./setup.sh` (default: no).
> Skip with `SKIP_GUI=1 ./setup.sh`.

---

### Monitoring Stack

```bash
./setup-monitoring.sh
```

Installs **kube-prometheus-stack** (Prometheus + Grafana) with:
- A pre-built **Crossplane dashboard** showing managed resource health, reconcile errors, and provider status
- A **ServiceMonitor** that scrapes `crossplane-system` metrics every 30 s
- Auto port-forwards on startup

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | `http://localhost:3000` | admin / crossplane-local |
| Prometheus | `http://localhost:9090` | — |

```bash
# Remove the monitoring stack
./setup-monitoring.sh --uninstall
```

---

### Example Compositions

Ready-to-run Crossplane examples using **provider-kubernetes** (no cloud credentials required — works fully locally).

```bash
./examples/apply.sh          # install provider, XRD, Composition, optional claim
./examples/apply.sh --all    # install everything without prompting
./examples/destroy.sh        # remove all example resources in safe order
```

**What the example creates:**

A developer submits an `AppNamespace` claim — Crossplane provisions:
1. A Kubernetes **Namespace** labelled with `owner` and `environment`
2. A **ResourceQuota** (CPU / memory limits)
3. A **LimitRange** (default container limits)

```bash
# Apply the example claim
kubectl apply -f examples/03-claims/my-app-namespace.yaml

# See what was provisioned
kubectl get appnamespace my-app -n default
kubectl get namespace my-app-dev
kubectl get resourcequota -n my-app-dev

# Delete (Crossplane removes all managed resources automatically)
kubectl delete -f examples/03-claims/my-app-namespace.yaml
```

---

## Lifecycle Scripts

| Script | Purpose |
|--------|---------|
| `./setup.sh` | Create the local environment from scratch |
| `./teardown.sh` | Stop cluster, clean kubeconfig, optional image prune |
| `./update.sh` | Upgrade Crossplane chart and providers in-place |
| `./setup-gui.sh` | Install a visual dashboard |
| `./setup-monitoring.sh` | Install Prometheus + Grafana |
| `./examples/apply.sh` | Deploy example compositions |
| `./examples/destroy.sh` | Remove example compositions |

```bash
# Teardown options
./teardown.sh             # interactive
./teardown.sh --all       # remove everything without prompts
CLUSTER_NAME=my-xp ./teardown.sh

# Update options
./update.sh                             # interactive
./update.sh --yes                       # non-interactive
./update.sh --crossplane-only           # only upgrade the Helm chart
./update.sh --providers-only            # only upgrade installed providers
CROSSPLANE_CHART_VERSION=2.3.0 ./update.sh
```

---

## Useful Commands

```bash
# Crossplane
kubectl get pods -n crossplane-system
kubectl get crds | grep crossplane
kubectl api-resources | grep crossplane.io
kubectl get provider

# Cluster (standard)
kind get clusters
kind delete cluster --name crossplane-local

# Cluster (lightweight)
k3d cluster list
k3d cluster delete crossplane-local
colima status

# Terminal UI
k9s
```

---

## Customising the Cluster

**Standard** — edit `configs/kind-config.yaml`:
- Number of worker nodes
- Host port mappings (useful for ingress controllers)

**Lightweight** — edit `configs/k3d-config.yaml`:
- Number of agent nodes
- Disabled components (Traefik, local-storage)

Or point to your own config at runtime:

```bash
KIND_CONFIG_PATH=/path/to/my-kind.yaml ./setup.sh
K3D_CONFIG_PATH=/path/to/my-k3d.yaml ./setup.sh
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker info` fails | Start Docker Desktop / Docker Engine |
| Pods stuck in `Pending` | Increase Docker Desktop / Colima memory allocation |
| `kind create cluster` times out | Ensure Docker has internet access for image pulls |
| `k3d cluster create` fails | Check Colima is running: `colima status` |
| `helm install` fails | Run `helm repo update` and retry |
| Free disk shows `0 GiB` on macOS | Update to latest — was a known bug (fixed in CP-KP-0001) |
| Tools not found after install (Windows) | Restart PowerShell or add install path to `$PATH` |
| Crossplane pods crash-looping | Check logs: `kubectl logs -n crossplane-system -l app=crossplane` |
| Provider stuck `Installing` | Check: `kubectl describe provider <name>` |

For Crossplane-specific issues see the [official docs](https://docs.crossplane.io).
