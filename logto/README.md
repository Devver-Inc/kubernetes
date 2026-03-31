# Logto

Déploiement de Logto, plateforme d'identité et d'authentification OAuth2/OIDC, avec sa base de données PostgreSQL.

## Fichiers

| Fichier | Description |
|---|---|
| `namespace.yaml` | Namespace `devver-logto` |
| `configmap.yaml` | Configuration Logto (ENDPOINT, ADMIN_ENDPOINT) |
| `secret-postgres.yaml` | Credentials PostgreSQL (à remplir avant déploiement) |
| `deployment-postgres.yaml` | Déploiement PostgreSQL 17 |
| `svc-postgres.yaml` | Service PostgreSQL sur le port 5432 |
| `pvc-postgres.yaml` | Volume persistant pour les données PostgreSQL (Longhorn) |
| `deployment-logto.yaml` | Déploiement Logto (`svhd/logto:latest`) |
| `svc-logto.yaml` | Service Logto (ports 3001 et 3002) |
| `ingress-logto.yaml` | Ingress Traefik pour l'interface Logto |
| `ingress-auth-logto.yaml` | Ingress Traefik pour le endpoint d'authentification |

## Architecture

```
Logto (port 3001 — UI admin, port 3002 — API auth)
   └── PostgreSQL 17 (port 5432, stockage Longhorn)
```

## Installation

```bash
# 1. Namespace
kubectl apply -f namespace.yaml

# 2. Renseigner les credentials dans secret-postgres.yaml puis appliquer
kubectl apply -f secret-postgres.yaml
kubectl apply -f configmap.yaml

# 3. Base de données
kubectl apply -f pvc-postgres.yaml
kubectl apply -f deployment-postgres.yaml
kubectl apply -f svc-postgres.yaml

# 4. Logto
kubectl apply -f deployment-logto.yaml
kubectl apply -f svc-logto.yaml
kubectl apply -f ingress-logto.yaml
kubectl apply -f ingress-auth-logto.yaml
```

## Notes

- Logto initialise automatiquement le schéma de base de données au premier démarrage.
- Le stockage PostgreSQL utilise Longhorn — s'assurer que Longhorn est installé et opérationnel avant le déploiement.
