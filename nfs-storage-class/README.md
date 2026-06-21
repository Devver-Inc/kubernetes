# NFS Storage Class

Migration de Longhorn vers une StorageClass NFS avec support des snapshots pour Kasten K10.

## Prérequis

- ArgoCD installé sur le cluster
- NAS Ugreen avec un partage NFS configuré :
  - NFSv4.1 activé
  - Option `no_root_squash` activée
  - IPs des nodes K8s autorisées
- Modifier `storage/nfs/storageclass.yaml` avec l'IP et le chemin de ton NAS avant de déployer

## Structure

```
├── storage/
│   ├── argocd-apps/                    # Applications ArgoCD (gérées par ArgoCD)
│   │   ├── argo-app-snapshot-crds.yaml       # CRDs VolumeSnapshot
│   │   ├── argo-app-snapshot-controller.yaml # Contrôleur de snapshots
│   │   └── argo-app-nfs-csi.yaml             # Driver CSI NFS
│   └── nfs/                            # Manifests appliqués manuellement
│       ├── storageclass.yaml                 # StorageClass nfs-csi (default)
│       ├── volumesnapshotclass.yaml          # VolumeSnapshotClass pour Kasten
│       └── patch-longhorn-default.yaml       # Retire Longhorn comme default
```

## Ordre de déploiement

### Étape 1 — CRDs VolumeSnapshot

Les CRDs doivent être installés en premier, avant tout le reste.

```bash
kubectl apply -f storage/argocd-apps/argo-app-snapshot-crds.yaml
```

Attendre que les CRDs soient bien enregistrés :

```bash
kubectl wait --for=condition=established \
  crd/volumesnapshotclasses.snapshot.storage.k8s.io \
  --timeout=60s
```

### Étape 2 — Snapshot Controller

Le contrôleur qui gère le cycle de vie des VolumeSnapshots.

```bash
kubectl apply -f storage/argocd-apps/argo-app-snapshot-controller.yaml
```

### Étape 3 — NFS CSI Driver

Le driver CSI qui permet à Kubernetes de provisionner des volumes sur le NAS NFS.

```bash
kubectl apply -f storage/argocd-apps/argo-app-nfs-csi.yaml
```

Attendre que le driver soit opérationnel :

```bash
kubectl -n kube-system wait --for=condition=ready pod \
  -l app=csi-nfs-controller \
  --timeout=120s
```

### Étape 4 — StorageClass, VolumeSnapshotClass et migration Longhorn

> **Avant cette étape**, éditer `storage/nfs/storageclass.yaml` et remplacer :
> - `192.168.1.X` → IP du NAS Ugreen
> - `/volume1/k8s` → chemin du partage NFS

```bash
kubectl apply -f storage/nfs/storageclass.yaml
kubectl apply -f storage/nfs/volumesnapshotclass.yaml
kubectl apply -f storage/nfs/patch-longhorn-default.yaml
```

`patch-longhorn-default.yaml` retire l'annotation `is-default-class` de Longhorn.
`storageclass.yaml` la positionne sur `nfs-csi`.

## Vérification

```bash
# Vérifier que nfs-csi est bien la StorageClass par défaut
kubectl get storageclass

# Vérifier que la VolumeSnapshotClass est présente avec l'annotation Kasten
kubectl get volumesnapshotclass

# Vérifier que les apps ArgoCD sont synchées
kubectl get applications -n argocd
```

## Migration des PVCs Longhorn

La méthode recommandée avec Kasten :

1. Créer un backup de chaque application depuis Kasten (stockage Longhorn)
2. Supprimer l'application et ses PVCs
3. Restaurer via Kasten — Kasten recréera les PVCs sur la StorageClass par défaut (`nfs-csi`)
