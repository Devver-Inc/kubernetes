# ArgoCD — Application racine d'un cluster

Ce dossier est un **chart Helm** : l'Application racine (app-of-apps) d'un
cluster `<org>-<env>`. La pipeline de `cluster-k8s-deployment`
(`ansible/playbooks/06-argocd-bootstrap.yml`) installe ArgoCD puis crée cette
Application racine avec les paramètres du cluster — **rien n'est écrit par
cluster dans ce repo**.

```
argocd/
  values.yaml                     # paramètres (fournis par la pipeline) + versions figées
  templates/
    projects.yaml                 # AppProjects platform / clients
    applications/                 # une Application par composant
    applicationsets/              # déploiements clients (argocd-client-deployment/<org>-<env>/...)
  legacy-prod/                    # fichiers du cluster de prod actuel (appliqués à la main)
```

## Paramètres (passés par la pipeline)

| Valeur | Source |
|---|---|
| `cluster.org`, `cluster.env` | nom du cluster `<org>-<env>` |
| `cluster.domain` | `<org>-<env>.<base_domain>` (Terraform) |
| `cluster.ingressIP` | IP MetalLB de Traefik (Terraform) |
| `nfs.server`, `nfs.share` | partage NFS dédié au cluster (Terraform) |
| `git.kubernetes.revision` | `kubernetes_git_revision` (Terraform) — branche en test, tag en prod |

## Vagues (sync waves)

| Wave | Applications |
|---|---|
| −6 | AppProjects `platform`, `clients` |
| −5 | `argocd` (ArgoCD se gère lui-même) |
| −4 | `external-secrets`, `snapshot-crds` |
| −3 | `platform-secrets` (namespaces, stores Vault, secrets de la stack, repos Argo), `snapshot-controller`, `csi-driver-nfs` |
| −2 | `storage` (StorageClass `nfs-<org>-<env>` sur le partage du cluster) |
| −1 | `cert-manager` |
| 0 | `cert-manager-issuers`, `traefik-middlewares`, `external-dns` (désactivé) |
| 1 | `kasten` (désactivé) |
| 2 | `minio`, `logto`, `mongo-db` |
| 3 | `backend-service`, `frontend-app`, `landing-page`, `documentation-app`, `uptime-kuma` |
| 4 | ApplicationSets `client-deployment`, `client-mongo` |

Chaque vague attend que les Applications de la précédente soient *Healthy*
(contrôle de santé des Applications dans `argocd-cm`, posé par l'Application
`argocd`). Un composant bloqué (ex: secret à `CHANGEME` dans Vault) bloque
les vagues suivantes jusqu'à ce qu'il soit corrigé.

## Volontairement absent pour l'instant

- **DNS / exposition publique** : `dnsTarget` vide et `external-dns`
  désactivé — à configurer avec le Traefik frontal et les enregistrements
  Cloudflare (étape ultérieure).
- **Kasten** : désactivé (`components.kasten`), configuration à revoir.

## Tester le rendu

```bash
helm template root argocd/ --set cluster.org=vr27,cluster.env=dev,\
cluster.domain=vr27-dev.devver.app,nfs.server=192.168.10.5,nfs.share=/volume1/NFS_K8S_VR27_DEV
```
