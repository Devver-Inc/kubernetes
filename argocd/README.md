# ArgoCD

Configuration ArgoCD pour le déploiement continu GitOps de l'infrastructure Devver.

## Fichiers

| Fichier | Description |
|---|---|
| `applicationset.yaml` | ApplicationSet pour les déploiements multi-tenant via le chart Helm |
| `argocd-cm.yaml` | ConfigMap ArgoCD (paramètres généraux) |
| `argocd-rbac-cm.yaml` | Politiques de contrôle d'accès (RBAC) |
| `ingress.yaml` | Ingress Traefik pour l'interface web ArgoCD |

## Fonctionnement

L'`ApplicationSet` génère automatiquement des `Application` ArgoCD pour chaque client/projet. Il utilise le [helm-chart-deployment-template](../helm-chart-deployment-template/) pour déployer les applications à partir des valeurs définies par projet.

## Installation

```bash
# Installer ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace

# Appliquer les configurations
kubectl apply -f argocd-cm.yaml
kubectl apply -f argocd-rbac-cm.yaml
kubectl apply -f ingress.yaml
kubectl apply -f applicationset.yaml
```

## Accès

L'interface ArgoCD est accessible via l'Ingress Traefik configuré dans `ingress.yaml`.

Mot de passe admin initial :
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```
