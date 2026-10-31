# Secrets d'un nouveau cluster : Vault + External Secrets Operator

Procédure pour les **nouveaux clusters** créés par
[`cluster-k8s-deployment`](https://github.com/Devver-Inc/cluster-k8s-deployment).
Le cluster de prod actuel n'est pas concerné.

## Principe

- **Aucun secret dans git.** Toutes les valeurs sont dans Vault (VM on-prem,
  console `https://vault.devver.app`) sous :

  ```
  kubernetes-cluster/<org>/<env>/<app>                   stack Devver
  kubernetes-cluster/<org>/<env>/clients/<namespace>/*   déploiements clients (écrits par le backend)
  ```

- **External Secrets Operator** (`argocd/application/eso-vault-app.yaml`)
  recopie ces valeurs dans des Secrets Kubernetes classiques. Les noms et les
  clés sont les mêmes qu'avant, donc les Deployments n'ont pas changé.
- **Le cluster s'authentifie à Vault** avec ses ServiceAccounts (auth Kubernetes
  `k8s-<org>-<env>`). Chaque accès est limité par une policy :

  | Qui | Store ESO | Peut lire |
  |---|---|---|
  | SA `external-secrets-system/eso-platform` | ClusterSecretStore `vault-platform` (namespaces `devver.app/secrets-tier=platform`) | `<org>/<env>/*` sauf `clients/` |
  | SA `external-secrets-system/eso-ghcr` | ClusterSecretStore `vault-ghcr` (namespaces `devver.app/needs-ghcr=true`) | `<org>/<env>/ghcr` |
  | SA `vault-reader` / `vault-reader-mongo` d'un namespace client | SecretStore `vault` / `vault-mongo` du namespace | `<org>/<env>/clients/<ce namespace>/*` |
  | SA `devver-backend-service/backend-service` (backend Devver) | — | lecture et écriture sur `<org>/<env>/clients/*` |

## Qui crée quoi

| Étape (pipeline `provision-cluster.yml`) | Outil | Résultat |
|---|---|---|
| `detect` | `terraform/vault/k8s-secrets.tf` | mount `kubernetes-cluster`, auth `k8s-<org>-<env>`, policies, rôles. **Aucune valeur.** |
| `prepare-secrets` (avant toute VM) | `ansible/playbooks/05-vault-seed.yml` | **initialisation des valeurs** (générées, fixes, copies des secrets communs, `CHANGEME`) ; arrêt si un secret VM ou bloquant manque |
| `configure` | `05-vault-k8s.yml` | token reviewer `kube-system/vault-auth`, config de l'auth (API + CA) |
| `configure` | `06-argocd-bootstrap.yml` | ArgoCD + Application racine (`argocd/`), qui déploie toute la stack par vagues ; mot de passe admin Argo et `ARGOCD_API_KEY` poussés dans Vault |
| Saisie | console Vault, à la main | secrets VM du cluster ; secrets communs une seule fois ; Logto après l'installation |

Le catalogue est `ansible/vars/vault-k8s-secrets.yml` (cluster-k8s-deployment).
Une clé existante n'est **jamais** réécrite, sauf une clé commune encore à
`CHANGEME`, recopiée dès que la valeur commune existe.

## Garde-fou : pas de pod tant qu'un secret n'est pas renseigné

**Tous** les ExternalSecrets portent le contrôle `devver.app/vault-check` : ceux
de `platform-secrets`, le `ghcr-secret` et ceux des charts clients app et
Mongo. Ce contrôle est un template ESO qui **échoue si une valeur lue dans Vault
est vide, ne contient que des espaces ou vaut `CHANGEME`** (quelle que soit la
casse).

| Situation | Effet |
|---|---|
| Chemin ou clé absent dans Vault | ExternalSecret `SecretSyncedError` (erreur ESO native), Secret non créé |
| Valeur vide ou `CHANGEME` | ExternalSecret `SecretSyncedError` avec le nom de la clé, Secret non créé |
| Secret absent | les pods qui le référencent restent en `CreateContainerConfigError` (aucune référence n'est `optional`) ; pour `ghcr-secret` : `ImagePullBackOff` ; pour `cloudflare-dns` : certificats en attente |
| La valeur est saisie | ESO crée le Secret au refresh suivant (ou `force-sync`), et le pod **démarre seul**, sans restart |
| Un Secret déjà valide devient invalide (valeur effacée par erreur) | ESO **garde l'ancien Secret** et passe en erreur : les pods continuent de tourner |

Pour voir ce qui bloque :

```bash
kubectl get externalsecret -A | grep -v SecretSynced
kubectl -n <ns> describe externalsecret <nom>   # "cle X vide ou CHANGEME dans Vault"
```

Toute nouvelle ExternalSecret doit inclure ce contrôle : helper `vaultCheck`
dans `_helpers.tpl` de chaque chart, à placer dans
`target.template.metadata.annotations`.

## Catalogue des secrets de la stack

| Chemin `kubernetes-cluster/<org>/<env>/…` | Clé | Classe | Consommé par (Secret K8s) |
|---|---|---|---|
| `cloudflare` | `api_token` | **commun** (token Cloudflare *Zone:DNS:Edit*) | `cert-manager/cloudflare-dns`, `external-dns/cloudflare-api-key` |
| `ghcr` | `username`, `token` | **commun** (PAT `read:packages`) | `ghcr-secret` dans chaque namespace `needs-ghcr` |
| `github` | `token` | **commun** (PAT d'écriture sur `argocd-client-deployment`) | `backend-secret` → `GITHUB_TOKEN` |
| `argocd-repos` | `kubernetes`, `client-deployment` | **commun** (clés privées SSH des deploy keys, lecture seule) | Secrets de repo d'ArgoCD (`argocd/repo-*`) |
| `minio` | `root_user` / `root_password` | fixe `devver-admin` / généré | `minio-credentials`, `backend-secret` → `STORAGE_*` |
| `logto-postgres` | `username` / `password` | fixe `logto` / généré | `logto-postgres-secret` |
| `backend` | `ENCRYPTION_KEY` | généré (hex 64) | `backend-secret`. ⚠️ **ne jamais la changer** sans re-chiffrer la base |
| `backend` | `DEPLOY_AGENT_SECRET`, `GIT_TOKEN_SECRET` | généré | `backend-secret` |
| `backend` | `ARGOCD_API_KEY` | **auto après installation** (pipeline) | `backend-secret` |
| `backend` | `LOGTO_CLIENT_ID`, `LOGTO_SECRET`, `LOGTO_WEBHOOK_SIGNING_KEY` | **à saisir après l'install de Logto** (non bloquant pour la pipeline) | `backend-secret` |
| `backend` | `VAULT_AUTH_MOUNT`, `VAULT_ROLE`, `VAULT_KV_PREFIX` | fixe | `backend-secret` |
| `argocd` | `admin_password` | **auto après installation** (copié depuis Argo) | — (connexion à l'UI) |

**Secrets communs** : saisis **une seule fois** dans
`devver-infra-deployment/shared/<chemin>` (mêmes noms de clés), copiés dans
chaque nouveau cluster par la pipeline. Un cluster peut ensuite surcharger sa
copie dans `kubernetes-cluster/<org>/<env>/<chemin>`.

## Procédure : nouveau cluster

**Prérequis (une fois pour toutes)** :
- 2 deploy keys SSH **en lecture seule** sur GitHub (`Devver-Inc/kubernetes`,
  `Devver-Inc/argocd-client-deployment`) ; leurs clés privées dans
  `devver-infra-deployment/shared/argocd-repos` (`kubernetes`,
  `client-deployment`) ;
- `devver-infra-deployment/shared/ghcr` (`username`, `token`),
  `shared/github` (`token`), `shared/cloudflare` (`api_token`).

**Par cluster** :
1. Créer son **partage NFS dédié** sur le NAS (ex. `/volume1/NFS_K8S_<ORG>_<ENV>`),
   avec la règle NFS : lecture/écriture, squash **Aucun mappage**, sécurité
   `AUTH_SYS`, async ; mêmes permissions de dossier que le partage de la prod.
   Lire la section [Stockage NFS : règle du NAS](#stockage-nfs--règle-du-nas).
2. Copier `terraform/clusters/_template` vers `clusters/<org>-<env>` (dont
   `nfs_server`, `nfs_share`, `kubernetes_git_revision`), pousser, puis lancer
   *Provision cluster* (`workflow_dispatch`, `org=<org>-<env>`). Le 1er
   lancement prépare tous les secrets et s'arrête en listant ce qui manque.
3. Saisir les secrets VM (`devver-infra-deployment/<org>/<env>`), relancer
   le même workflow : VMs, RKE2, Vault, ArgoCD, puis la stack par vagues.
4. Après l'installation : créer l'application backend et le webhook dans
   Logto, saisir `LOGTO_*` dans `backend`, forcer la synchro :
   ```bash
   kubectl -n devver-backend-service annotate externalsecret backend-secret \
     force-sync=$(date +%s) --overwrite
   ```
   Le backend démarre seul dès que le Secret existe.

## Opérations courantes

- **Changer un secret (rotation).** Créer une nouvelle version dans la console,
  forcer la synchro (`force-sync`, voir plus haut), puis faire un `rollout
  restart` du Deployment concerné. Les pods ne relisent pas leurs variables
  d'environnement à chaud.
  - Mots de passe MinIO et Postgres : il faut **aussi** changer le mot de passe
    dans le service lui-même. Le Secret ne sert qu'à l'initialisation.
  - `ENCRYPTION_KEY` : ne pas la changer.
- **Ajouter un secret à la stack.**
  1. Ajouter la clé au catalogue `ansible/vars/vault-k8s-secrets.yml`
     (`cluster-k8s-deployment`).
  2. L'ajouter à l'ExternalSecret concerné : `platform-secrets/templates/externalsecrets.yaml`,
     ou `backend-service/templates/externalsecret.yaml` pour le backend.
  3. Relancer la pipeline (job `prepare-secrets`, playbook `05-vault-seed.yml`) :
     seule la nouvelle clé est créée.
- **Supprimer un cluster.** Le job `vault-cleanup` retire l'auth, les
  policies et les rôles, purge `devver-infra-deployment/<org>/<env>`
  (`delete_all_versions`) et tous les chemins de `kubernetes-cluster/<org>/<env>/`,
  clients compris, **toutes versions comprises**. Ces secrets ne sont pas
  récupérables ensuite : à exporter avant si besoin.

## Stockage NFS : règle du NAS

Constaté sur le NAS (Ugreen) lors du premier déploiement complet (`vr27-dev`) :

- **root** (aucun squash) peut tout faire ;
- un **utilisateur non-root** n'a accès qu'aux dossiers **dont il est
  propriétaire** — les droits « autres » sont ignorés, même en `777` ;
- la **racine du volume** (dossier `pvc-…` créé par le driver NFS) doit rester à
  root : attribuée à un autre utilisateur, elle lui devient inaccessible ;
- l'**uid 1000** correspond à un compte du NAS : il est refusé partout, même
  dans un dossier qui lui appartient.

Règle pour toute application dont l'image ne tourne pas en root : un
initContainer (root) crée un **sous-dossier** du volume et l'attribue à l'uid
de l'image ; l'application écrit dans ce sous-dossier (ex. `subPath`). Ne
jamais utiliser l'uid 1000.

| Application | uid | Dossier attribué |
|---|---|---|
| Postgres (Logto), `postgres:17-alpine` | 70 | `pgdata` (`PGDATA`) |
| MongoDB, `mongo:7.0` | 999 | `db` (`storage.subPath`, monté sur `/data/db`) |
| uptime-kuma | 0 (root) | — ; base **SQLite** imposée (`UPTIME_KUMA_DB_TYPE`), le MariaDB intégré tourne sous l'uid 1000 |
| MinIO, frontend, landing, doc | 0 (root) | — |

## Dépannage

- **Une Application reste `Degraded` / `Progressing` et plus rien ne se
  déploie.** Une vague attend que la précédente soit *Healthy* : tant qu'elle
  ne l'est pas, la synchro de l'Application `root` reste « Running » et aucun
  nouveau commit n'est appliqué. Corriger la cause, puis relancer la synchro :
  ```bash
  kubectl -n argocd patch application root --type merge \
    -p '{"status":{"operationState":{"phase":"Terminating"}}}'
  kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
  ```
  Un composant dont l'échec ne doit pas geler le cluster porte l'annotation
  `devver.app/non-blocking` (aujourd'hui : `backend-service`, en attente de
  ses secrets Logto) — voir `argocd/README.md`.
- **`Permission denied` / `CrashLoopBackOff` d'une base de données** : voir
  [Stockage NFS : règle du NAS](#stockage-nfs--règle-du-nas).
- **`ImagePullBackOff` sur MinIO** : `minio/minio` n'est plus publié sur Docker
  Hub ; les nouveaux clusters utilisent `pgsty/minio` (version figée dans
  `argocd/values.yaml`, `images.minio`).
- **Enregistrements `_acme-challenge` qui s'accumulent dans Cloudflare**
  (limite de 200 enregistrements dans la zone) : cert-manager doit supprimer
  son TXT après chaque validation. Les nouveaux clusters le font ; le cluster
  de prod actuel en laisse un à chaque renouvellement (144 supprimés le
  31/10/2026, cause à corriger côté prod). Nettoyage des TXT de plus de 2
  jours (un challenge en cours n'est jamais touché) :
  ```bash
  export VAULT_ADDR=https://vault.devver.app
  C=$(vault kv get -field=api_token devver-infra-deployment/shared/cloudflare)
  Z=$(curl -s -H "Authorization: Bearer $C" "https://api.cloudflare.com/client/v4/zones?name=devver.app" | jq -r '.result[0].id')
  LIMIT=$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%S)
  for p in 1 2 3 4; do
    curl -s -H "Authorization: Bearer $C" "https://api.cloudflare.com/client/v4/zones/$Z/dns_records?type=TXT&per_page=100&page=$p" \
    | jq -r --arg l "$LIMIT" '.result[] | select((.name|startswith("_acme-challenge.")) and .created_on < $l) | "\(.id) \(.name)"'
  done | sort -u | while read id name; do
    curl -s -X DELETE -H "Authorization: Bearer $C" "https://api.cloudflare.com/client/v4/zones/$Z/dns_records/$id" \
    | jq -r --arg n "$name" '"\(if .success then "supprimé" else "ÉCHEC" end) \($n)"'
  done
  unset C
  ```

## Si Vault est indisponible (scellé, VM arrêtée)

Vault tourne sur une seule VM avec unseal manuel.

- **Ce qui continue de fonctionner :** les Secrets déjà synchronisés restent en
  place, car ESO ne les supprime pas en cas d'erreur. Les pods tournent et
  redémarrent normalement.
- **Ce qui est bloqué :**
  - les nouveaux déploiements clients (le backend ne peut plus écrire) ;
  - les nouveaux namespaces ;
  - les rotations.

  Les ExternalSecrets passent en `SecretSyncedError`.
- **Rétablir :** desceller Vault (`vault operator unseal`, clés Shamir). ESO
  reprend tout seul au refresh suivant.

## Vérifications utiles

```bash
# Auth Vault ↔ cluster
vault read auth/k8s-<org>-<env>/config
vault list auth/k8s-<org>-<env>/role

# Isolation : un namespace client ne lit que son dossier
kubectl -n <ns-client> get secretstore vault          # Ready
kubectl -n <ns-client> get externalsecret             # SecretSynced
```
