# Backend : écrire les secrets des déploiements clients dans Vault

**Pour :** l'équipe backend. **Statut :** à implémenter.
L'infra est prête sur les nouveaux clusters ; le cluster de prod actuel n'est
pas concerné.

## Pourquoi

Aujourd'hui, quand le backend déploie un projet client, il commite dans
`Devver-Inc/argocd-client-deployment` un `values.yaml` qui contient des
secrets **en clair** :
- `DEVVER_SECRET`, identique pour tous les clients ;
- les mots de passe Mongo (`values-mongo.yaml`) ;
- les connection strings.

Ces valeurs restent dans l'historique git, même après suppression du projet.

**Cible :** le backend écrit les secrets dans **Vault** et ne commite plus que
de la configuration non sensible. Dans le cluster, External Secrets Operator
recopie les valeurs de Vault dans des Secrets Kubernetes.

## Ce qui est déjà en place côté infra

- **Les chemins Vault** de chaque projet client :

  ```
  kubernetes-cluster/<org>/<env>/clients/<namespace>/app     → env vars du conteneur
  kubernetes-cluster/<org>/<env>/clients/<namespace>/mongo   → credentials Mongo
  ```

  - `<org>/<env>` identifie le cluster (ex : `acme/prod`). Ce n'est **pas**
    l'organisation Devver du client.
  - `<namespace>` = `lower(<org slug client>)-lower(<project slug>)`, exactement
    le namespace que crée le chart (ex : `johnny-kaktus`).
- **Le chart client** (`helm-chart-deployment-template`, avec
  `secrets.enabled: true`) injecte **toutes** les clés de `.../app` comme
  variables d'environnement du conteneur.
- **Le chart Mongo** construit `MONGO_ROOT_USERNAME`, `MONGO_ROOT_PASSWORD` et
  `MONGO_CONNECTION_STRING` à partir de `.../mongo`.
- **Le backend s'authentifie à Vault avec son ServiceAccount** (auth
  Kubernetes), comme ESO. Il n'a **aucun secret Vault** : il présente le jeton
  du SA `backend-service`, que le kubelet monte dans le pod et renouvelle
  automatiquement. Il reçoit dans son environnement (Secret `backend-secret` +
  ConfigMap `backend-config`) :

  | Variable | Contenu |
  |---|---|
  | `VAULT_ADDR` | `https://vault.devver.app` |
  | `VAULT_AUTH_MOUNT` | `k8s-<org>-<env>` (mount de l'auth Kubernetes du cluster) |
  | `VAULT_ROLE` | `backend` |
  | `VAULT_KV_PREFIX` | `kubernetes-cluster/<org>/<env>` |

  Droits : création, lecture, mise à jour et suppression sur
  `kubernetes-cluster/<org>/<env>/clients/*`, et rien d'autre. Vault vérifie
  que le jeton est bien celui du SA `backend-service` du namespace
  `devver-backend-service`.

`VAULT_KV_PREFIX` évite de coder l'org et l'env du cluster en dur. Les chemins clients sont donc `${VAULT_KV_PREFIX}/clients/<ns>/...` (en
KV v2, l'API insère `data/` après le mount : `kubernetes-cluster/data/<org>/<env>/...`).

## Ce que le backend doit faire

### 1. Client Vault

- Lib Node : [`node-vault`](https://www.npmjs.com/package/node-vault), ou de
  simples appels HTTP (API KV v2).
- **Login :** `POST /v1/auth/${VAULT_AUTH_MOUNT}/login` avec
  `{ "role": "${VAULT_ROLE}", "jwt": "<contenu de /var/run/secrets/kubernetes.io/serviceaccount/token>" }`
  (`node-vault` : `kubernetesLogin({ role, jwt })`, en passant `mount_point`).
  On obtient un token Vault valable 1 h (renouvelable jusqu'à 4 h).
  **Relire le fichier du jeton à chaque login** : le kubelet le remplace
  régulièrement. Le plus simple est de refaire le login quand le token Vault
  expire ou qu'un appel répond 403.
- **Écriture (KV v2) :** `POST /v1/kubernetes-cluster/data/<org>/<env>/clients/<ns>/app`
  avec `{ "data": { "CLE": "valeur", ... } }`.
- **Point d'attention :** une écriture KV v2 **remplace tout le secret**. Pour
  modifier une seule clé, il faut relire, fusionner, puis réécrire.

### 2. Déploiement d'un projet, dans cet ordre

1. **Calculer `<ns>`** avec la même règle que le chart. Refuser les noms
   réservés : `kube-*`, `default`, `argocd`, `external-secrets-system`,
   `devver-*`, `cert-manager`, `external-dns`, `traefik`, `metallb-system`,
   `kasten-io`.
2. **Écrire `.../clients/<ns>/app` dans Vault** :
   - `DEVVER_SECRET` : **générer une valeur unique par projet**, 48 caractères
     alphanumériques aléatoires. On abandonne `dev-secret-123`, partagé par
     tous. À voir aussi côté deploy-agent.
   - Toutes les variables d'environnement **sensibles** saisies par
     l'utilisateur.
3. **Si Mongo est demandé, écrire `.../clients/<ns>/mongo`** avec
   `{ "username": "root", "password": "<généré>" }`. Le mot de passe doit être
   **alphanumérique uniquement** : il est inséré tel quel dans la connection
   string.
4. **Seulement ensuite**, commiter les values dans `argocd-client-deployment`.

   **`values.yaml`** : plus aucun secret. `DEVVER_SECRET` est retiré de
   `container.env`.

   ```yaml
   secrets:
     enabled: true
   container:
     env:                      # NON sensible uniquement
       NODE_ENV: production
       DEVVER_WIDGET_URL: ...
   ```

   **`values-mongo.yaml`** : plus de bloc `auth`.

   ```yaml
   secrets:
     enabled: true
   ```

   `cluster.org`, `cluster.env` et `imagePullSecret.mode: eso` sont injectés par
   l'ApplicationSet. Le backend n'a pas à les écrire.

5. **Ne jamais écrire de valeur vide ni `CHANGEME`.** Le garde-fou de
   l'infra refuse alors de créer le Secret, et le pod du projet ne démarre pas
   (`CreateContainerConfigError`). Une variable sans valeur doit être
   **omise**, pas écrite avec `""`. Il faut valider ça côté UI et API.
6. **Si Vault répond en erreur** (scellé, injoignable, 403) : le déploiement
   échoue avec un message clair et **rien n'est commité**.

> Pourquoi Vault avant git : si le commit arrive d'abord, ArgoCD déploie le
> projet, l'ExternalSecret ne trouve pas le chemin, et le pod reste en
> `CreateContainerConfigError` jusqu'à l'écriture dans Vault.

### 3. Lecture côté application cliente

- **Variables d'environnement :** rien à faire. Elles arrivent dans le
  conteneur comme avant, via le Secret `<ns>-env` injecté en `envFrom`.
- **Connection string Mongo :** à lire depuis le Secret `<ns>-mongo-secret`,
  clé `MONGO_CONNECTION_STRING`. Le backend ne doit plus la construire ni la
  mettre dans `container.env`. Si l'app doit la recevoir en variable
  d'environnement, le backend copie la valeur qu'il a lui-même générée dans
  `.../app`.

### 4. Modifier une variable d'environnement d'un projet

1. Relire `.../app`, fusionner la modification, réécrire.
2. ESO resynchronise sous 15 min (`refreshInterval`). Pour un effet immédiat, le backend
   déclenche :
   - l'annotation `force-sync=<timestamp>` sur l'ExternalSecret
     `<ns>-env` ;
   - puis un rollout restart du Deployment.

   Ces deux appels passent par l'API Kubernetes ou l'API ArgoCD (action
   `restart`).

### 5. Supprimer un projet

1. Commit de suppression dans `argocd-client-deployment`, comme aujourd'hui.
2. Supprimer ses secrets :
   `DELETE /v1/kubernetes-cluster/metadata/<org>/<env>/clients/<ns>/app`
   (et `/mongo`). Cela efface toutes les versions.

### 6. Variables sensibles ou non : à décider côté produit

Deux options :
- **Simple :** toutes les variables saisies par l'utilisateur vont dans Vault,
  et `container.env` ne garde que la config Devver (widget, `NODE_ENV`).
- **Fine :** une case « secret » par variable dans l'UI ; seules les variables
  cochées vont dans Vault.

L'infra supporte les deux. Si une même clé est définie dans `container.env` et
dans Vault, la valeur de `container.env` l'emporte (règle Kubernetes
`env` > `envFrom`). Il faut donc éviter les doublons.

## Points à confirmer avec l'infra

- **Format de `ENCRYPTION_KEY`.** Sur un nouveau cluster, elle est générée en
  hex de 64 caractères (32 octets). Si le backend attend un autre format
  (base64, longueur différente), le signaler : il faudra la régénérer
  **avant** le premier démarrage.
- **`LOGTO_CLIENT_ID`** est désormais une variable lue depuis Vault, au lieu
  d'être dans la config.

## Migration des projets existants

Pas avant le passage sur un nouveau cluster. Un script one-shot devra :
1. lire chaque `values*.yaml` ;
2. pousser les secrets dans Vault ;
3. réécrire les values sans secrets, avec `secrets.enabled: true` ;
4. générer un `DEVVER_SECRET` propre à chaque projet, puis redéployer.

Les valeurs déjà présentes dans l'historique git doivent être considérées comme
compromises et **remplacées** lors de cette migration, pas simplement
déplacées.
