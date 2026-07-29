# Kubernetes — Infrastructure Devver

Ce dépôt contient l'ensemble des manifestes Kubernetes et configurations Helm pour l'infrastructure de Devver. Il couvre le réseau, le stockage, la sécurité, les sauvegardes, le déploiement continu et les applications.

## Architecture globale

```
Internet
   │
   ▼
MetalLB (LoadBalancer IP)
   │
   ▼
Traefik (Ingress Controller + TLS)
   │
   ├── cert-manager     → Certificats Let's Encrypt (DNS01 via Cloudflare)
   ├── external-dns     → Sync automatique DNS vers Cloudflare
   ├── crowdsec         → Détection d'intrusion sur les logs Traefik
   │
   ├── ArgoCD           → GitOps / déploiement continu
   ├── Kasten K10       → Sauvegardes Kubernetes (NFS sur NAS externe)
   │
   ├── frontend-app     → Application frontend Devver
   ├── landing-page     → Page d'accueil Devver
   ├── logto            → Fournisseur d'identité OAuth2/OIDC
   └── uptime-kuma      → Monitoring de disponibilité
```

Domaine principal : `devver.app` — HTTPS automatique sur tous les services.

## Contenu du dépôt

| Dossier | Description |
|---|---|
| [argocd/](argocd/) | GitOps avec ArgoCD et ApplicationSet multi-tenant |
| [cert-manager/](cert-manager/) | Émission automatique de certificats Let's Encrypt |
| [crowdsec/](crowdsec/) | Moteur de sécurité / détection d'intrusion |
| [external-dns/](external-dns/) | Synchronisation DNS automatique vers Cloudflare |
| [frontend-app/](frontend-app/) | Déploiement de l'application frontend |
| [helm-chart-deployment-template/](helm-chart-deployment-template/) | Chart Helm réutilisable pour déployer une app |
| [helm-chart-mongo-template/](helm-chart-mongo-template/) | Chart Helm StatefulSet MongoDB avec ReplicaSet et TLS |
| [vault/](vault/) | Déploiement HashiCorp Vault (gestion des secrets) |
| [kasten/](kasten/) | Sauvegardes et restauration Kubernetes |
| [landing-page/](landing-page/) | Déploiement de la landing page |
| [logto/](logto/) | Plateforme d'authentification avec PostgreSQL |
| [nfs-storage-class/](nfs-storage-class/) | NFS CSI Driver — stockage persistant via NAS externe |
| [longhorn/](longhorn/) | Stockage distribué persistant (remplacé par NFS en T3) |
| [traefik/](traefik/) | Reverse proxy et répartition de charge |
| [uptime-kuma/](uptime-kuma/) | Monitoring de disponibilité des services |

## Prérequis

- Cluster Kubernetes opérationnel
- `kubectl` configuré avec accès cluster
- `helm` installé
- Accès à GitHub Container Registry (`ghcr.io/devver-inc`)
- Domaine configuré sur Cloudflare avec token API

## Ordre d'installation recommandé

1. **NFS CSI Driver** — stockage persistant via NAS externe (requis par la plupart des apps)
2. **MetalLB + Traefik** — réseau et ingress
3. **cert-manager** — certificats TLS
4. **external-dns** — gestion DNS
5. **ArgoCD** — déploiement continu (gère ensuite tous les composants suivants)
6. **Vault** — gestion des secrets
7. **Kasten** — sauvegardes
8. **Crowdsec** — sécurité
9. **Applications** — logto, frontend-app, landing-page, uptime-kuma
