# helm-chart-deployment-template

Chart Helm générique pour déployer des applications conteneurisées sur un cluster Kubernetes.

## Prérequis

- [Helm](https://helm.sh/docs/intro/install) installé
- Accès au cluster Kubernetes configuré (fichier kubeconfig)
- Secret `ghcr-secret` présent dans le namespace cible pour les images privées GitHub Container Registry

## Connexion au cluster Kubernetes

Importer la configuration du cluster avant d'utiliser Helm :

```bash
export KUBECONFIG=/home/$HOME/backend-kubeconfig.yaml
```

---

## Ressources créées par le chart

Le chart déploie les ressources Kubernetes suivantes :

| Ressource | Description |
|-----------|-------------|
| `Namespace` | Namespace dédié nommé `<organisation>-<projet>` |
| `Deployment` | Déploiement de l'application avec le nombre de replicas configuré |
| `Service` | Service ClusterIP exposant le port 80 |
| `Ingress` | Ingress TLS via Traefik avec certificat Let's Encrypt (DNS CloudFlare) |
| `PersistentVolumeClaim` | Deux volumes persistants (`/app` et `/root`) via Longhorn |
| `Secret` | Credentials pour le pull d'images depuis un registry privé |

L'URL d'accès générée suit le format : `https://<organisation>.<projet>.<domaine>`

---

## Utilisation

### Créer un déploiement

Avec les valeurs par défaut (définies dans `values.yaml`) :

```bash
helm install NOM-DEPLOIEMENT ./helm-chart-deployment-template
```

En surchargeant certaines valeurs via arguments :

```bash
helm install NOM-DEPLOIEMENT ./helm-chart-deployment-template \
  --set project.name=mon-projet \
  --set organization.name=mon-organisation \
  --set container.image=mon-registry/mon-image:tag
```

En fournissant un fichier de valeurs externe (recommandé pour les déploiements automatisés) :

```bash
helm install NOM-DEPLOIEMENT ./helm-chart-deployment-template \
  -f /chemin/vers/mon-values.yaml
```

> **Cas ArgoCD / ApplicationSet :** ce chart est appliqué automatiquement par ArgoCD via ApplicationSet. Les valeurs sont lues depuis un repo externe et injectées via un fichier `values.yaml` dédié par application. Il n'est donc pas nécessaire de modifier `values.yaml` dans ce repo pour configurer un déploiement.

### Valeurs par défaut

Si une valeur n'est pas définie dans le fichier de values fourni, Helm utilise la valeur par défaut définie dans `values.yaml` de ce chart. Par exemple, si `replicaCount` n'est pas spécifié, le déploiement aura **1 replica**, ou si `resources` n'est pas défini, le conteneur aura **128Mi de RAM et 100m de CPU**.

### Modifier un déploiement existant

```bash
helm upgrade NOM-DEPLOIEMENT ./helm-chart-deployment-template \
  --set resources.requests.memory="256Mi" \
  --set resources.limits.memory="256Mi"
```

### Supprimer un déploiement

```bash
helm uninstall NOM-DEPLOIEMENT
```

### Lister les déploiements en cours

```bash
helm list
```

---

## Configuration

Tous les paramètres sont définis dans `values.yaml`. Le tableau ci-dessous décrit chaque variable configurable.

### Organisation & Projet

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `organization.name` | `orgt1` | Nom de l'organisation — utilisé dans le namespace et le hostname |
| `organization.domain` | `devver.app` | Domaine principal pour l'ingress |
| `project.name` | `projt1` | Nom du projet — utilisé dans le namespace et le hostname |

### Conteneur

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `container.image` | `ghcr.io/devver-inc/deploy-agent:latest` | Image Docker à déployer |
| `container.port` | `80` | Port exposé par le conteneur |
| `container.type` | `app` | Type de conteneur |
| `container.command` | `[]` | Commande de démarrage (optionnel) |
| `container.args` | `[]` | Arguments de la commande (optionnel) |
| `container.env` | voir values.yaml | Variables d'environnement injectées dans le conteneur |

### Ressources

Définir les mêmes valeurs pour `requests` et `limits`.

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `resources.requests.memory` | `128Mi` | Mémoire minimale allouée |
| `resources.limits.memory` | `128Mi` | Mémoire maximale autorisée |
| `resources.requests.cpu` | `100m` | CPU minimal alloué (en millicores, ex: `100m` = 0,1 CPU) |
| `resources.limits.cpu` | `100m` | CPU maximal autorisé |

> **Note CPU :** `1000m` = 1 CPU. On peut aussi utiliser un décimal : `1.5` = 1,5 CPU = `1500m`.

### Persistance

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `persistence.enabled` | `true` | Active ou désactive les volumes persistants |
| `persistence.app.size` | `10Gi` | Taille du volume monté sur `/app` |
| `persistence.app.mountPath` | `/app` | Répertoire de montage dans le conteneur |
| `persistence.app.storageClass` | `longhorn` | Classe de stockage Kubernetes |
| `persistence.root.size` | `5Gi` | Taille du volume monté sur `/root` |
| `persistence.root.mountPath` | `/root` | Répertoire de montage dans le conteneur |
| `persistence.root.storageClass` | `longhorn` | Classe de stockage Kubernetes |

### Réplication

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `replicaCount` | `1` | Nombre de replicas du pod |

---

## Structure du chart

```
helm-chart-deployment-template/
├── Chart.yaml                # Métadonnées du chart (nom, version)
├── values.yaml               # Valeurs de configuration par défaut
├── README.md                 # Documentation
└── templates/
    ├── _helpers.tpl          # Fonctions et macros réutilisables
    ├── namespace.yaml        # Création du Namespace
    ├── deployment.yaml       # Déploiement Kubernetes
    ├── service.yaml          # Service ClusterIP
    ├── ingress.yaml          # Ingress TLS (Traefik + Let's Encrypt)
    ├── pvc.yaml              # PersistentVolumeClaims (Longhorn)
    └── imagepullsecret.yaml  # Secret pour le pull d'images privées
```
