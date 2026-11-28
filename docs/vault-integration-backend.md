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
  kubernetes-cluster/<org>/<env>/clients/<namespace>/app        → env vars du conteneur
  kubernetes-cluster/<org>/<env>/clients/<namespace>/<moteur>   → env du conteneur de la base (mongo, postgres, valkey)
  ```

  - `<org>/<env>` identifie le cluster (ex : `acme/prod`). Ce n'est **pas**
    l'organisation Devver du client.
  - `<namespace>` = `p-<projectId>`, exactement le namespace que crée le chart
    quand les values portent `project.id` (deploy-agent v0.2+). Il ne change pas
    si l'org ou le projet est renommé, et le backend comme le git-gateway en
    déduisent l'adresse de l'agent : `deploy-agent.p-<projectId>.svc`. Sans
    `project.id` (cluster de prod actuel) : `lower(<org>)-lower(<projet>)`.
- **Le chart client** (`helm-chart-deployment-template`, avec
  `secrets.enabled: true`) injecte **toutes** les clés de `.../app` comme
  variables d'environnement du conteneur.
- **Le chart des services** (`helm-chart-service-template`, ApplicationSet
  `client-services`) injecte **toutes** les clés de `.../<moteur>` comme
  variables d'environnement du conteneur de la base.
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
  | `VAULT_KV_MOUNT` | `kubernetes-cluster` |
  | `VAULT_KV_PREFIX` | `<org>/<env>` |

  Droits : création, lecture, mise à jour et suppression sur
  `kubernetes-cluster/<org>/<env>/clients/*`, et rien d'autre. Vault vérifie
  que le jeton est bien celui du SA `backend-service` du namespace
  `devver-backend-service`.

`VAULT_KV_PREFIX` évite de coder l'org et l'env du cluster en dur. Les chemins clients sont donc `${VAULT_KV_PREFIX}/clients/<ns>/...` sous le mount `${VAULT_KV_MOUNT}` (en
KV v2, l'API insère `data/` après le mount : `kubernetes-cluster/data/<org>/<env>/...`).

Identité du cluster, également dans la ConfigMap `backend-config` : `DEVVER_CLUSTER_ID`
(`<org>-<env>`), `DEVVER_ORG`, `DEVVER_ENV`, `DEVVER_DOMAIN`. Ne jamais écrire un
domaine, une org ou un env en dur : voir la section « Fiche du cluster » de
`docs/vault-nouveau-cluster.md`.

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
   - **Aucune** connection string : le backend l'envoie à l'agent à chaque
     appel `/databases/*`, et l'injecte dans l'env des déploiements liés
     (`dbLinks`). Une rotation de mot de passe ne redémarre donc pas l'agent.
   - **Pas** les variables saisies par l'utilisateur : `.../app` devient
     l'environnement du deploy-agent lui-même, qui ne le transmet jamais aux
     apps clientes (liste blanche). Voir « Env des déploiements » ci-dessous.
3. **Pour chaque base, écrire `.../clients/<ns>/<moteur>`** : les clés sont
   exactement l'env du conteneur, valeurs générées par le backend (mots de
   passe en hex, insérés tels quels dans la connection string).

   | Moteur | Clés |
   |---|---|
   | `mongo` | `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `MONGO_KEYFILE` (base64, 756 octets max) |
   | `postgres` | `POSTGRES_USER`, `POSTGRES_PASSWORD` |
   | `valkey` | `VALKEY_PASSWORD` |
4. **Seulement ensuite**, commiter les values dans `argocd-client-deployment`,
   **sous le dossier du cluster** : `${GITHUB_PATH_PREFIX}/p-<projectId>/`
   (les ApplicationSets lisent `<org>-<env>/p-*`)
   (`GITHUB_PATH_PREFIX` = `<org>-<env>`, fourni par la ConfigMap du backend ;
   vide sur le cluster de prod actuel = racine du repo). L'ApplicationSet de
   chaque cluster ne lit que son dossier.

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

   **`services/<moteur>/values.yaml`** : une base, rendue par
   `helm-chart-service-template` (voir son `values.yaml`). Exemple Postgres :

   ```yaml
   project: { id: <projectId> }
   name: p-<projectId>-postgres
   image: { repository: postgres, tag: 18-alpine }
   args: [postgres, -c, shared_buffers=256MB, -c, max_connections=100, -c, max_wal_size=512MB]
   ports: [{ name: postgres, port: 5432 }]
   env: { PGDATA: /var/lib/postgresql/data/pgdata, POSTGRES_DB: postgres }
   secretEnv: { vaultKey: postgres }
   volume: { path: /var/lib/postgresql, size: 5Gi }
   shm: { sizeLimit: 256Mi }
   resources: { requests: { cpu: 250m, memory: 1536Mi }, limits: { cpu: "1", memory: 1536Mi } }
   ```

   `cluster.org`, `cluster.env`, `persistence.storageClass` (et, pour
   `values.yaml`, `imagePullSecret.mode: eso`) sont injectés par
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
- **Connection string d'une base :** construite par le backend depuis
  `.../<moteur>` et envoyée dans l'env du déploiement qui la demande (`dbLinks`).
  Le Service de la base est headless, nommé `p-<projectId>-<moteur>`.

### 4. Modifier une variable d'environnement d'un projet

1. Relire `.../app`, fusionner la modification, réécrire.
2. ESO resynchronise sous 15 min (`refreshInterval`). Pour un effet immédiat, le backend
   déclenche :
   - l'annotation `force-sync=<timestamp>` sur l'ExternalSecret
     `<ns>-env` ;
   - puis la suppression des pods du Deployment (API ArgoCD,
     `DELETE /api/v1/applications/<app>/resource?kind=Pod&...`) : leur
     ReplicaSet les recrée aussitôt avec le nouveau Secret.

   Pas de rollout restart ni d'action `restart` : l'annotation `restartedAt`
   n'est pas dans git, selfHeal l'annule dans la seconde et le pod ne
   redémarre jamais. Supprimer un pod n'est pas un écart avec git.

### 5. Supprimer un projet

1. Commit de suppression dans `argocd-client-deployment`, comme aujourd'hui.
2. Supprimer ses secrets :
   `DELETE /v1/kubernetes-cluster/metadata/<org>/<env>/clients/<ns>/app`
   (et `/<moteur>` de chaque base). Cela efface toutes les versions.

### 6. Env des déploiements (deploy-agent v0.2)

Un projet tourne dans **un** pod deploy-agent, qui lance une app par branche et
par service (« déploiement »). Chaque déploiement a son propre env (`API_URL` de
`main` ≠ celui de `feat-x`), et le code client ne doit jamais voir les secrets de
l'agent. Donc :

- L'env saisi par l'utilisateur va dans
  `${VAULT_KV_PREFIX}/clients/p-<projectId>/deployments/<deploymentId>`
  (couvert par les droits `clients/*` du rôle `backend`, rien à changer côté Vault).
- Il n'est **pas** synchronisé par ESO : le backend le lit au déploiement et
  l'envoie au deploy-agent dans le corps du `PUT /deployments/<deploymentId>`
  (appel interne, port 8080, fermé par NetworkPolicy). L'agent le passe au seul
  processus de ce déploiement et ne l'écrit jamais sur disque.
- Le pod de l'agent ne monte aucun jeton de ServiceAccount : le code client qui y
  tourne ne peut pas s'authentifier auprès de Vault.
- Modifier une variable = réécrire ce chemin puis redéployer (`devver deploy`) ;
  pas de `force-sync` ni de rollout du pod de l'agent.
- `container.env` ne garde que la configuration non sensible de l'agent
  (`DEVVER_PROJECT_ID`, `DEVVER_PREVIEW_DOMAIN`, `DEVVER_WIDGET_URL`...).

## Points à confirmer avec l'infra

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
