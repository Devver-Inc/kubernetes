# Kasten K10 — Sauvegarde Kubernetes

[Kasten K10](https://www.kasten.io/) est une solution de backup/restore pour Kubernetes. Il protège les namespaces, volumes (PVC), et ressources Kubernetes via des policies de sauvegarde planifiées.

Interface accessible sur : **https://kasten.devver.app**

---

## Fonctionnement rapide

1. Kasten scanne les namespaces du cluster
2. On définit des **policies** pour sauvegarder des apps (namespaces)
3. Les snapshots de volumes Longhorn sont créés via `VolumeSnapshotClass`
4. Les données sont exportées vers un **Location Profile** (ici le NAS via NFS)

---

## Composants de ce dossier

### `nfs-backup-storageclass.yaml`
StorageClass pointant vers le NAS via le driver `nfs.csi.k8s.io`.

- Serveur NAS : `192.168.10.5`
- Share : `/volume1/NFS_K8S_DEVVER_BACKUP`
- NFS v3, `onDelete: archive` (les données ne sont pas supprimées si le PV est supprimé)

### `pvc-nfs-backup.yaml`
PVC que Kasten utilise pour stocker ses sauvegardes sur le NAS.

> **Kasten a besoin d'un PVC existant pour configurer un Location Profile de type "File System".**
> Ce PVC doit être créé dans le namespace `kasten-io` avant de configurer le profil dans l'interface.

```bash
kubectl apply -f nfs-backup-storageclass.yaml
kubectl apply -f pvc-nfs-backup.yaml
```

Ensuite dans l'interface Kasten : **Settings → Location Profiles → New Profile → File System** → indiquer le PVC `pvc-kasten-backup`.


### `volumestorageclass-longhorn.yaml`
Déclare la `VolumeSnapshotClass` Longhorn avec l'annotation `k10.kasten.io/is-snapshot-class: "true"` pour que Kasten puisse créer des snapshots de volumes.

### `ingress.yaml`
Expose l'interface Kasten via Traefik avec TLS Let's Encrypt (cert-manager).

---

## Ordre d'installation

1. Installer Kasten via Helm dans le namespace `kasten-io`
2. Appliquer la StorageClass NFS et le PVC
3. Appliquer la VolumeSnapshotClass Longhorn
4. Configurer le Location Profile dans l'UI en pointant sur le PVC `pvc-kasten-backup`
5. Créer les policies de backup par namespace
