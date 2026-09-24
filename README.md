# 🏠 Kubernetes Homelab

> Production-grade Kubernetes homelab for experimenting and learning
## 📁 Repository Structure

- **`ansible/`** - Infrastructure automation with Ansible
- **`kubernetes/`** - Kubernetes manifests and applications
- **`docs/`** - Architecture and setup documentation
- **`scripts/`** - Utility scripts and tools

## 🚀 Quick Links

- [Ansible Setup](ansible/README.md)
- [Kubernetes Apps](kubernetes/README.md)
- [Architecture Overview](docs/architecture.md)
- [Hardware Details](docs/hardware.md)

## 🏗️ Current Setup

- **Nodes**: 2x Intel NUCs (32GB RAM total), 1x MacMini (16GB) Proxmox - VM Debian
- **OS**: Ubuntu 24.04 LTS, Debian 13
- **K8s**: K3s v1.33.6
- **Automation**: Ansible
- **LoadBalancer**: MetalLB
- **Ingress**: Traefik + Gateway API
- **AdGuard**: Self-hosted DNSoHTTPS and Ad Blocker

## 📖 Documentation

See the [docs](docs/) directory for detailed documentation.

## 🎯 Project Goals

1. Learn production Kubernetes practices
2. Automate everything with IaC
3. Build portfolio-worthy infrastructure
4. Prepare for SRE/Platform Engineering roles

## 👤 Author

Igor Bond - [GitHub](https://github.com/igorbnd)
