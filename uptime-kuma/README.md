# Uptime Kuma

Déploiement d'Uptime Kuma, outil de monitoring de disponibilité des services.

## Fichiers

| Fichier | Description |
|---|---|
| `namespace.yaml` | Namespace `devver-uptime-kuma` |
| `deployment.yaml` | Déploiement Uptime Kuma (`louislam/uptime-kuma:2.5.5`) |
| `svc.yaml` | Service exposant le port 3001 |
| `pvc.yaml` | Volume persistant pour la base de données de monitoring (Longhorn) |
| `ingress.yaml` | Ingress Traefik avec TLS Let's Encrypt |

## Installation

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f svc.yaml
kubectl apply -f ingress.yaml
```

## Notes

- Uptime Kuma stocke sa configuration et son historique dans un volume Longhorn — s'assurer que Longhorn est opérationnel avant le déploiement.
- L'interface est accessible via l'Ingress Traefik configuré dans `ingress.yaml`.
- Lors du premier accès, créer un compte administrateur depuis l'interface web.

## Sondes

Sondes configurées dans l'interface (tags : frontend, backend, auth, storage, database, infra, backup, prod) :

| Sonde | Cible | Tags |
|---|---|---|
| Landing Page / (www) | https://devver.app/, https://www.devver.app/ | frontend, prod |
| Frontend App | https://app.devver.app/ | frontend, prod |
| Documentation | https://docs.devver.app/ | frontend |
| Backend API | https://app.devver.app/api/ (keyword `"statusCode":404`, réponse NestJS) | backend, prod |
| Logto / Logto (auth) | https://logto.devver.app/api/status, https://auth.devver.app/api/status | auth, prod |
| MinIO API / Console | https://minio-api.devver.app/minio/health/live, https://minioc.devver.app/ | storage, prod |
| MongoDB | TCP `mongodb.devver-mongodb.svc.cluster.local:27017` | database, prod |
| ArgoCD | https://argocd.devver.app/healthz | infra |
| Kasten K10 | https://kasten.devver.app/k10/ | infra, backup |

- Le deployment utilise `strategy: Recreate` : SQLite sur NFS ne supporte pas deux pods qui écrivent en même temps pendant un rolling update (corruption `SQLITE_CORRUPT`).
