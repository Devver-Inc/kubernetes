# helm-chart-mongo-template

Chart Helm pour déployer MongoDB en StatefulSet avec ReplicaSet sur Kubernetes.

## Fonctionnement

- **StatefulSet** : chaque replica a son propre PVC Longhorn et un DNS stable
- **ReplicaSet MongoDB** : 1 primary (écritures) + N secondaries (lecture/HA). Un Job post-install initialise automatiquement le ReplicaSet au premier déploiement
- **TLS** : cert-manager génère automatiquement un certificat signé par le CA interne `internal-ca`. Tous les flux sont chiffrés (client → mongo et inter-membres)
- **Auth** : user root créé au démarrage via les variables `MONGO_INITDB_ROOT_*`
- **Keyfile** : clé inter-membres générée automatiquement au premier déploiement et stable aux upgrades suivants

## Intégration ArgoCD

Ce chart est déployé automatiquement par l'ApplicationSet `devver-client-mongo`.

**Pour activer une MongoDB sur un projet :** déposer un fichier `values-mongo.yaml` dans le dossier `clientX/projetX/` du repo `argocd-client-deployment`.

**Pour la supprimer :** retirer le fichier — ArgoCD supprime toutes les ressources, PVC inclus (données perdues définitivement).

Le namespace `clientX-projetX` doit déjà exister (créé par le chart deployment). Si vous déployez ce chart seul sans le chart deployment, mettre `namespace.create: true`.

## Structure du repo argocd-client-deployment

```
clientX/
  projetX/
    values.yaml           # chart deployment (app)
    values-mongo.yaml     # chart mongo (optionnel)
```

## Fichier values-mongo.yaml

Nom du fichier à respecter impérativement : **`values-mongo.yaml`**

```yaml
namespace:
  create: false   # false si le chart deployment est déjà déployé sur ce projet

organization:
  name: "monorga"       # nom de l'organisation (ex: devver)
  domain: "devver.app"

project:
  name: "monprojet"     # nom du projet (ex: api)

auth:
  rootUsername: "root"
  rootPassword: "motdepassefort"   # en clair pour l'instant, Vault à venir

replicaCount: 1   # 1 = standalone, 3 = haute disponibilité recommandée

persistence:
  size: "10Gi"          # taille du PVC par replica
  storageClass: "longhorn"

resources:
  requests:
    memory: "512Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

## Ressources créées

Pour `organization.name: orgt1` et `project.name: projt1` :

| Ressource | Nom |
|-----------|-----|
| Namespace | `orgt1-projt1` |
| StatefulSet | `orgt1-projt1-mongo` |
| Service ClusterIP | `orgt1-projt1-mongo:27017` |
| Service Headless | `orgt1-projt1-mongo-headless` |
| Secret credentials | `orgt1-projt1-mongo-secret` |
| Certificate TLS | `orgt1-projt1-mongo-tls` |
| PVC par replica | `data-orgt1-projt1-mongo-0` |

## Connection string

Disponible dans le secret `orgt1-projt1-mongo-secret`, clé `MONGO_CONNECTION_STRING` :

```
mongodb://root:pass@orgt1-projt1-mongo:27017/?tls=true&tlsCAFile=/etc/mongo/tls/ca.crt
```

Pour les apps qui se connectent depuis le même namespace, monter le secret et référencer `MONGO_CONNECTION_STRING`. Le CA est disponible dans le secret `orgt1-projt1-mongo-tls`, clé `ca.crt`.

Pour ignorer la vérification TLS (pratique en dev) :
```
mongodb://root:pass@orgt1-projt1-mongo:27017/?tls=true&tlsAllowInvalidCertificates=true
```

## Passage en haute disponibilité

Changer `replicaCount: 3` dans le values. Le ReplicaSet MongoDB élit automatiquement un primary parmi les 3 pods. En cas de crash du primary, élection d'un nouveau primary en ~10 secondes. Les écritures vont toujours sur le primary, les lectures peuvent être distribuées sur les secondaries.

## Prérequis cluster

- cert-manager installé avec le `ClusterIssuer` **`internal-ca`** (voir `kubernetes/cert-manager/clusterissuer-selfsigned.yaml`)
- StorageClass `longhorn` disponible
- Ressources minimum par replica : 512Mi RAM, 10Gi disque
