# platform-secrets

Ce chart amène dans un cluster les secrets de la stack Devver. Les valeurs
viennent de Vault, sous `kubernetes-cluster/<org>/<env>/`, et sont synchronisées
par External Secrets Operator (ESO).

Il crée :

| Objet | Rôle |
|---|---|
| Namespaces de la stack (wave −1) | labels `devver.app/secrets-tier=platform` et/ou `devver.app/needs-ghcr=true` |
| SA `eso-platform`, `eso-ghcr` (namespace ESO) | identités présentées à Vault (auth `k8s-<org>-<env>`) |
| ClusterSecretStore `vault-platform` | tous les secrets de la stack (sauf `clients/`), réservé aux namespaces `secrets-tier=platform` |
| ClusterSecretStore `vault-ghcr` | uniquement `ghcr`, pour les namespaces `needs-ghcr=true` |
| ExternalSecrets | `backend-secret`, `minio-credentials`, `logto-postgres-secret`, `cloudflare-dns`, `cloudflare-api-key` : mêmes noms et mêmes clés que les anciens Secrets en clair |
| ClusterExternalSecret `ghcr-secret` | pull secret `ghcr.io` dans chaque namespace `needs-ghcr=true`, clients compris (remplace Reflector) |

Chaque ExternalSecret porte le contrôle `devver.app/vault-check` : une valeur
vide ou à `CHANGEME` dans Vault empêche la création du Secret, et donc le
démarrage des pods qui l'utilisent. Le détail est dans la procédure.

## Prérequis

- **ESO installé** (`argocd/application/eso-vault-app.yaml`, version 2.11.0,
  API `external-secrets.io/v1`).
- **Cluster créé par `cluster-k8s-deployment`** avec un nom `<org>-<env>`. Le
  workflow crée la structure Vault et l'auth Kubernetes, et initialise les
  valeurs.

## Utilisation

```bash
helm template platform-secrets ./platform-secrets \
  --set cluster.org=acme --set cluster.env=prod | kubectl apply -f -
```

Avec ArgoCD (phase 2) : une Application en wave −2, avec `cluster.org` et
`cluster.env` en paramètres Helm.

Valeurs principales :

| Clé | Défaut | |
|---|---|---|
| `cluster.org` / `cluster.env` | requis | chemin Vault et auth `k8s-<org>-<env>` |
| `vault.server` | `https://vault.devver.app` | |
| `vault.caProvider` | `{}` | à renseigner uniquement si le certificat de Vault n'est pas reconnu depuis le cluster |
| `namespaces` | stack Devver | namespaces créés et labellisés |

Pour la procédure complète (catalogue des clés, saisie dans la console,
rotation, Vault indisponible), voir
[docs/vault-nouveau-cluster.md](../docs/vault-nouveau-cluster.md).
