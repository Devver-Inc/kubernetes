# Longhorn

Configuration du stockage distribué Longhorn pour le cluster Kubernetes.

## Fichiers

| Fichier | Description |
|---|---|
| `longhorn-values.yaml` | Valeurs Helm (réplicas, chemin des données, sélecteurs de nœuds) |
| `longhorn-sc.yaml` | StorageClass Longhorn |

## Fonctionnement

Longhorn fournit du stockage bloc persistant et distribué sur les nœuds worker du cluster. Les volumes sont répliqués (2 réplicas par défaut) pour garantir la haute disponibilité des données.

Les données sont stockées dans `/mnt/longhorn` sur les nœuds worker.

## Installation

```bash
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn -n longhorn-system --create-namespace \
  -f longhorn-values.yaml

# Créer la StorageClass
kubectl apply -f longhorn-sc.yaml
```

## Notes

- Longhorn doit être installé **avant** tout déploiement utilisant du stockage persistant (logto, uptime-kuma, kasten).
- L'interface web Longhorn est accessible via le service `longhorn-frontend` dans le namespace `longhorn-system`.
- Kasten K10 utilise Longhorn pour les snapshots de volumes ([voir kasten/](../kasten/)).
