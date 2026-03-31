# frontend-app

Déploiement de l'application frontend Devver sur Kubernetes.

## Fichiers

| Fichier | Description |
|---|---|
| `namespace.yaml` | Namespace `devver-frontend-app` |
| `deployment.yaml` | Déploiement de l'image `ghcr.io/devver-inc/frontend-app:latest` |
| `svc.yaml` | Service ClusterIP exposant le port 80 |
| `ingress.yaml` | Ingress Traefik avec TLS Let's Encrypt |

## Installation

```bash
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f svc.yaml
kubectl apply -f ingress.yaml
```

## Notes

- L'image est hébergée sur GitHub Container Registry (`ghcr.io/devver-inc/frontend-app`).
- Un `imagePullSecret` doit être présent dans le namespace pour accéder au registre privé.
- Le certificat TLS est géré automatiquement par cert-manager.
