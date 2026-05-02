# helm-chart-mongo-template — Documentation technique

Ce document explique le rôle de chaque fichier du chart et les décisions d'architecture.

## Structure du chart

```
helm-chart-mongo-template/
├── Chart.yaml
├── values.yaml
├── values-mongo.example.yaml
├── README.md
├── README-dev.md
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── secret.yaml
    ├── secret-keyfile.yaml
    ├── certificate.yaml
    ├── configmap-init.yaml
    ├── statefulset.yaml
    ├── service.yaml
    ├── service-headless.yaml
    └── job-init-replicaset.yaml
```

---

## Chart.yaml

Métadonnées du chart : nom `mongo-template`, version, appVersion MongoDB (`7.0`). Pas de dépendances externes.

---

## values.yaml

Valeurs par défaut du chart. Tout ce qui est défini ici peut être surchargé dans le `values-mongo.yaml` du client.

Sections importantes :
- `namespace.create` : `true` pour créer le namespace, `false` si déjà créé par le chart deployment
- `organization` / `project` : construisent tous les noms de ressources (`nomorga-nomprojet-mongo`)
- `auth` : credentials root MongoDB — en clair pour l'instant, Vault à venir
- `replicaCount` : nombre de pods MongoDB. `1` = standalone, `3` = ReplicaSet HA
- `replicaSetName` : nom interne du ReplicaSet MongoDB (`rs0` par défaut)
- `persistence` : taille du PVC et StorageClass par replica
- `image` : image MongoDB officielle, tag fixé à `7.0` pour la stabilité

---

## templates/_helpers.tpl

Fonctions Helm réutilisées dans tous les templates :

- `mongo-template.fullname` → `nomorga-nomprojet`
- `mongo-template.mongoName` → `nomorga-nomprojet-mongo` (nom de toutes les ressources MongoDB)
- `mongo-template.namespace` → `nomorga-nomprojet`
- `mongo-template.labels` → labels communs appliqués à toutes les ressources
- `mongo-template.selectorLabels` → labels utilisés par les selectors Service et StatefulSet

---

## templates/namespace.yaml

Crée le namespace `nomorga-nomprojet` uniquement si `namespace.create: true`.

En pratique avec ArgoCD, le namespace est déjà créé par le chart deployment — ce fichier ne génère rien (`namespace.create: false` par défaut dans le values client). Il sert uniquement si ce chart est déployé seul sans le chart deployment.

---

## templates/secret.yaml

Secret principal `nomorga-nomprojet-mongo-secret` contenant :
- `MONGO_ROOT_USERNAME` / `MONGO_ROOT_PASSWORD` : credentials root lus depuis le values
- `MONGO_CONNECTION_STRING` : connection string complète préconstruite avec TLS, prête à être injectée dans les apps clientes

Ce secret est **déterministe** — son contenu ne change que si le values change. Pas de génération aléatoire → pas d'out of sync ArgoCD.

---

## templates/secret-keyfile.yaml

Secret séparé `nomorga-nomprojet-mongo-keyfile` contenant uniquement le `mongodb-keyfile`.

**Pourquoi séparé ?** Le keyfile est une clé aléatoire générée une seule fois (`randAlphaNum 756`). Helm utilise `lookup` pour relire la valeur existante sur le cluster aux upgrades suivants. ArgoCD ne peut pas faire ce `lookup` (il tourne en mode dry-run sans accès cluster), ce qui provoquerait un out of sync permanent si le keyfile était dans le secret principal.

En le séparant, l'ApplicationSet peut ignorer les diffs sur ce secret via `ignoreDifferences`.

**Rôle du keyfile** : MongoDB l'exige pour l'authentification interne entre les membres du ReplicaSet (inter-pods). Tous les pods partagent la même clé. Elle n'a pas besoin d'être mémorisée — elle est juste stable.

---

## templates/certificate.yaml

Ressource cert-manager `Certificate` qui génère automatiquement un certificat TLS signé par le CA interne `internal-ca` (ClusterIssuer self-signed défini dans `kubernetes/cert-manager/clusterissuer-selfsigned.yaml`).

Le certificat contient tous les SANs nécessaires :
- DNS du Service ClusterIP (pour les clients applicatifs)
- DNS du Service Headless (pour la communication inter-membres du ReplicaSet)
- DNS individuel de chaque pod StatefulSet (`pod-N.headless.namespace.svc.cluster.local`)
- IP `127.0.0.1` (pour les health checks locaux dans le pod)

cert-manager stocke le certificat généré dans le secret `nomorga-nomprojet-mongo-tls` avec les clés `tls.crt`, `tls.key` et `ca.crt`.

---

## templates/configmap-init.yaml

ConfigMap contenant le script `init-replicaset.sh` exécuté par le Job post-install.

Ce script :
1. Attend que le pod-0 MongoDB soit joignable via son FQDN complet (`pod-0.headless.namespace.svc.cluster.local`)
2. Vérifie si le ReplicaSet est déjà initialisé (`rs.status().ok`)
3. Si non : construit la liste des membres (un par replica) et appelle `rs.initiate()`
4. Si oui : ne fait rien (idempotent — safe à rejouer aux upgrades)

La connexion utilise TLS avec le CA du secret cert-manager monté dans le Job.

---

## templates/statefulset.yaml

Cœur du chart. StatefulSet avec `replicaCount` pods.

**InitContainers (s'exécutent avant MongoDB) :**

1. `fix-keyfile` (busybox) : copie le keyfile depuis le secret vers un `emptyDir`, fixe le propriétaire à `999:999` (uid de l'user `mongodb` dans l'image officielle) et les permissions à `400`. MongoDB refuse de démarrer si le keyfile appartient à root ou a des permissions trop ouvertes.

2. `prepare-tls` (busybox) : concatène `tls.crt` + `tls.key` en un fichier `combined.pem` (format requis par MongoDB), copie le `ca.crt`. Fixe également owner `999:999` et permissions `400`.

**Container principal `mongodb` :**

Lance l'entrypoint officiel de l'image avec des `args` (pas `command`) — important car `command` bypasse l'entrypoint qui s'occupe de créer le user root au premier démarrage.

Arguments passés à `mongod` :
- `--replSet rs0` : active le mode ReplicaSet
- `--keyFile` : auth inter-membres
- `--tlsMode requireTLS` : force TLS sur toutes les connexions
- `--tlsCertificateKeyFile` : combined.pem préparé par l'initContainer
- `--tlsCAFile` : CA pour valider les certs clients
- `--tlsAllowConnectionsWithoutCertificates` : TLS obligatoire mais le client n'a pas besoin de présenter son propre cert (pas de mTLS strict côté client)

**Volumes :**
- `data` (PVC Longhorn) : données MongoDB persistantes
- `scripts` (ConfigMap) : script init-replicaset.sh
- `keyfile-secret` (Secret) : keyfile brut depuis le secret
- `keyfile` (emptyDir) : keyfile avec les bonnes permissions (préparé par fix-keyfile)
- `tls-secret` (Secret) : cert/key bruts depuis cert-manager
- `tls` (emptyDir) : combined.pem + ca.crt avec les bonnes permissions (préparé par prepare-tls)

**volumeClaimTemplates :**
Kubernetes crée automatiquement un PVC par pod (`data-nomorga-nomprojet-mongo-0`, `-1`, `-2`...). Ces PVC ne sont **jamais supprimés** par Helm uninstall — protection des données. Suppression manuelle nécessaire en cas de recréation complète.

---

## templates/service.yaml

Service `ClusterIP` `nomorga-nomprojet-mongo:27017` — point d'entrée pour les apps clientes dans le même namespace. Route vers le primary MongoDB (le StatefulSet selector pointe vers tous les pods, MongoDB accepte les connexions sur tous les pods mais redirige les écritures vers le primary via le driver).

---

## templates/service-headless.yaml

Service Headless (`clusterIP: None`) `nomorga-nomprojet-mongo-headless` — ne route pas le trafic mais crée les entrées DNS individuelles pour chaque pod (`pod-N.headless.namespace.svc.cluster.local`). Requis par le StatefulSet pour que les membres du ReplicaSet se trouvent entre eux via DNS stable.

`publishNotReadyAddresses: true` : les pods sont enregistrés en DNS même avant d'être Ready — nécessaire au démarrage pour que le Job d'init puisse atteindre le pod-0 avant que les health checks passent.

---

## templates/job-init-replicaset.yaml

Job Helm hook (`post-install`, `post-upgrade`) qui initialise le ReplicaSet MongoDB après chaque déploiement.

- `hook-delete-policy: before-hook-creation` : supprime le Job précédent avant d'en créer un nouveau
- `backoffLimit: 10` : réessaie jusqu'à 10 fois si MongoDB n'est pas encore prêt
- `activeDeadlineSeconds: 300` : timeout de 5 minutes

Le Job tourne dans un pod séparé (pas dans le pod MongoDB) et se connecte via le FQDN du pod-0. C'est pourquoi le script utilise la connection string complète avec host, et non `localhost`.

---

## Flux de démarrage complet

```
helm install
    │
    ├── Création : Namespace, Secrets, Certificate, ConfigMap, Services
    │
    ├── StatefulSet crée pod-0
    │   ├── InitContainer fix-keyfile    → prépare /etc/mongo/keyfile
    │   ├── InitContainer prepare-tls   → prépare /etc/mongo/tls/combined.pem
    │   └── Container mongodb démarre   → entrypoint crée user root + lance mongod
    │
    └── Job post-install
        ├── Attend que pod-0 réponde sur son FQDN
        ├── rs.status().ok == 0 → rs.initiate({ membres... })
        └── ReplicaSet initialisé → Job Completed
```

---

## Relation avec l'ApplicationSet ArgoCD

`applicationset-mongo.yaml` dans `kubernetes/argocd/` surveille le repo `argocd-client-deployment`. Dès qu'un fichier `values-mongo.yaml` apparaît dans `clientX/projetX/`, ArgoCD crée une Application qui déploie ce chart avec ce values.

`ignoreDifferences` sur les secrets dont le nom finit par `-mongo-keyfile` : ArgoCD ne considère pas les diffs sur ce secret comme un out of sync, ce qui évite une boucle de reconciliation infinie due au keyfile généré aléatoirement.
