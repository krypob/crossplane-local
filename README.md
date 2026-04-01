# Crossplane Local Environment

One-command setup for a fully functional [Crossplane](https://crossplane.io) local environment using **kind** (Kubernetes in Docker) and **Helm**.

---

## Prerequisites

> The only thing you must install manually before running the script is **Docker**.

| Tool | macOS | Linux | Windows |
|------|-------|-------|---------|
| Docker Desktop | [Download](https://www.docker.com/products/docker-desktop) | [Docs](https://docs.docker.com/engine/install/) | [Download](https://www.docker.com/products/docker-desktop) |

Everything else (kind, kubectl, helm, Crossplane CLI) is installed automatically.

---

## Minimum System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 8 GiB | 16 GiB |
| CPU cores | 4 | 6+ |
| Free disk space | 20 GiB | 40 GiB |

> **macOS / Windows (Docker Desktop):** allocate at least 8 GiB of memory in
> Docker Desktop → Settings → Resources → Memory.

---

## Quick Start

### macOS / Linux

```bash
# Clone the repo (skip if you already have it)
git clone <repo-url> crossplane-project
cd crossplane-project

# Make the script executable and run
chmod +x setup.sh
./setup.sh
```

The script will:
1. Ask which OS you are using
2. Display minimum requirements and ask for confirmation
3. Check your system resources (RAM, CPU, disk, Docker)
4. Install missing tools via Homebrew (macOS) or direct binaries (Linux)
5. Create a `crossplane-local` kind cluster (1 control-plane + 2 workers)
6. Add the Crossplane Helm repo and install Crossplane
7. Wait for all pods to become ready and print a status summary

### Windows (PowerShell — Administrator)

```powershell
# Allow local scripts to run
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the setup
.\setup.ps1
```

> **WSL 2 users:** run `./setup.sh` from your WSL terminal instead.

---

## Environment Variables (optional overrides)

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `crossplane-local` | Name of the kind cluster |
| `CROSSPLANE_NAMESPACE` | `crossplane-system` | Kubernetes namespace for Crossplane |
| `CROSSPLANE_CHART_VERSION` | *(latest)* | Pin a specific Crossplane Helm chart version |
| `KIND_VERSION` | `v0.25.0` | kind binary version to install |
| `KUBECTL_VERSION` | `v1.31.0` | kubectl version to install |
| `HELM_VERSION` | `v3.16.2` | Helm version to install |
| `KIND_CONFIG_PATH` | `configs/kind-config.yaml` | Path to a custom kind cluster config |
| `SKIP_CHECKS` | `0` | Set to `1` to skip resource checks |

Example:

```bash
CLUSTER_NAME=my-xp CROSSPLANE_CHART_VERSION=1.17.0 ./setup.sh
```

---

## Project Structure

```
crossplane-project/
├── setup.sh                    # Entry point — macOS / Linux
├── setup.ps1                   # Entry point — Windows (PowerShell)
├── scripts/
│   ├── common.sh               # Colors, logging, shared helpers
│   ├── requirements.sh         # Display and check system requirements
│   ├── install.sh              # Install kind, kubectl, helm, up
│   └── cluster.sh              # Create kind cluster, install Crossplane
└── configs/
    └── kind-config.yaml        # kind cluster layout (1 control-plane + 2 workers)
```

---

## What Gets Installed

| Tool | Purpose |
|------|---------|
| **kind** | Runs a Kubernetes cluster inside Docker containers |
| **kubectl** | CLI to interact with the cluster |
| **helm** | Installs Crossplane via the official Helm chart |
| **up** | Crossplane CLI for managing providers and compositions |
| **Crossplane** | Deployed into the `crossplane-system` namespace |

---

## Useful Commands After Setup

```bash
# Check Crossplane pods
kubectl get pods -n crossplane-system

# List all Crossplane CRDs
kubectl get crds | grep crossplane

# List available API resources from Crossplane
kubectl api-resources | grep crossplane.io

# Check all kind clusters
kind get clusters

# Delete the local cluster when done
kind delete cluster --name crossplane-local
```

---

## Customising the Cluster

Edit `configs/kind-config.yaml` to adjust:
- Number of worker nodes
- Port mappings (useful for ingress controllers)
- Custom pod/service CIDR ranges

Or point to your own config file:

```bash
KIND_CONFIG_PATH=/path/to/my-config.yaml ./setup.sh
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker info` fails | Start Docker Desktop / Docker Engine |
| Pods stuck in `Pending` | Increase Docker Desktop memory allocation |
| `kind create cluster` times out | Ensure Docker has internet access for image pulls |
| `helm install` fails | Run `helm repo update` and retry |
| Tools not found after install (Windows) | Restart PowerShell or add install path to `$PATH` |

For Crossplane-specific issues see the [official docs](https://docs.crossplane.io).
