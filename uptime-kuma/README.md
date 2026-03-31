# Uptime Kuma

Déploiement d'Uptime Kuma, outil de monitoring de disponibilité des services.

## Fichiers

| Fichier | Description |
|---|---|
| `namespace.yaml` | Namespace `devver-uptime-kuma` |
| `deployment.yaml` | Déploiement Uptime Kuma (`louislam/uptime-kuma:1`) |
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
