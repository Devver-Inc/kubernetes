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

| Étape | Outil | Résultat |
|---|---|---|
| Création du cluster (`create-cluster`) | `terraform/vault/k8s-secrets.tf` | mount `kubernetes-cluster`, auth `k8s-<org>-<env>`, policies, rôles. **Aucune valeur.** |
| Configuration (`configure`) | `ansible/playbooks/05-vault-k8s.yml` | token reviewer `kube-system/vault-auth`, config de l'auth (API + CA), **initialisation des valeurs** |
| Saisie | console Vault, à la main | valeurs qui viennent d'un tiers ou qui n'existent qu'après l'install |
| Déploiement | ArgoCD : ESO, puis chart `platform-secrets`, puis apps | Secrets K8s synchronisés |

Le playbook 05 suit le catalogue `ansible/vars/vault-k8s-secrets.yml`. Il ne
réécrit **jamais** une clé existante : on peut le relancer sans risque.

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

| Chemin `kubernetes-cluster/<org>/<env>/…` | Clé | Origine | Consommé par (Secret K8s) |
|---|---|---|---|
| `cloudflare` | `api_token` | **à saisir** (token Cloudflare *Zone:DNS:Edit*) | `cert-manager/cloudflare-dns`, `external-dns/cloudflare-api-key` |
| `ghcr` | `username`, `token` | **à saisir** (PAT `read:packages`) | `ghcr-secret` dans chaque namespace `needs-ghcr` |
| `github` | `token` | **à saisir** (PAT d'écriture sur `argocd-client-deployment`) | `backend-secret` → `GITHUB_TOKEN` |
| `minio` | `root_user` | fixe : `devver-admin` | `minio-credentials`, `backend-secret` → `STORAGE_ACCESS_KEY` |
| `minio` | `root_password` | généré | `minio-credentials`, `backend-secret` → `STORAGE_SECRET_KEY` |
| `logto-postgres` | `username` | fixe : `logto` | `logto-postgres-secret` |
| `logto-postgres` | `password` | généré | `logto-postgres-secret` |
| `backend` | `ENCRYPTION_KEY` | généré (hex 64) | `backend-secret`. ⚠️ **ne jamais la changer** sans re-chiffrer la base |
| `backend` | `DEPLOY_AGENT_SECRET`, `GIT_TOKEN_SECRET` | généré | `backend-secret` |
| `backend` | `LOGTO_CLIENT_ID`, `LOGTO_SECRET`, `LOGTO_WEBHOOK_SIGNING_KEY` | **à saisir après l'install de Logto** | `backend-secret` |
| `backend` | `ARGOCD_API_KEY` | **à saisir après l'install d'ArgoCD** | `backend-secret` |
| `backend` | `VAULT_AUTH_MOUNT`, `VAULT_ROLE` | fixe : `k8s-<org>-<env>`, `backend` (auth Kubernetes du backend, aucun secret) | `backend-secret` |
| `backend` | `VAULT_KV_PREFIX` | fixe : `kubernetes-cluster/<org>/<env>` | `backend-secret` |

Toutes les clés de `backend/` sont injectées dans `backend-secret`. La
configuration non sensible est dans `backend-service/configmap.yaml`.

## Procédure : nouveau cluster

1. **Créer le cluster.** Copier `terraform/clusters/_template` vers
   `clusters/<org>-<env>` et pousser. Le workflow *Provision cluster* crée la
   structure Vault, les VMs et RKE2, puis lance le playbook 05.
   À la fin du job `configure`, la liste des clés restées à `CHANGEME` est
   affichée.

2. **Saisir les secrets externes.** Console `https://vault.devver.app/ui` →
   *Secrets engines* → `kubernetes-cluster` → `<org>/<env>/`. Pour chaque
   chemin, *Create new version* et remplacer les `CHANGEME` de :
   - `cloudflare` → `api_token` ;
   - `ghcr` → `username`, `token` ;
   - `github` → `token`.

   Ces trois secrets sont nécessaires pour les certificats, le DNS et le pull
   des images.

3. **Déployer.** On passe par ArgoCD : ESO, puis `platform-secrets` (avec
   `cluster.org` et `cluster.env`), puis la stack. En attendant l'app-of-apps :

   ```bash
   helm template platform-secrets ./platform-secrets \
     --set cluster.org=<org> --set cluster.env=<env> | kubectl apply -f -
   kubectl get clustersecretstore   # vault-platform et vault-ghcr : Ready=True
   kubectl get externalsecret -A    # SecretSynced
   ```

   Tout démarre **sauf le backend** : son ExternalSecret reste en erreur
   (`cle LOGTO_SECRET vide ou CHANGEME…`) et son pod en
   `CreateContainerConfigError` tant que les clés Logto et ArgoCD ne sont pas
   saisies. C'est attendu.

4. **Saisir les secrets post-install.**
   - Dans Logto : créer l'application backend et le webhook. Saisir
     `LOGTO_CLIENT_ID`, `LOGTO_SECRET` et `LOGTO_WEBHOOK_SIGNING_KEY` dans
     `backend`.
   - Dans ArgoCD : `argocd account generate-token --account backend-api`, puis
     saisir le résultat dans `backend` → `ARGOCD_API_KEY`.

5. **Forcer la synchro**, sans attendre le refresh (15 min). Le pod du
   backend démarre seul dès que le Secret existe :

   ```bash
   kubectl -n devver-backend-service annotate externalsecret backend-secret \
     force-sync=$(date +%s) --overwrite
   ```

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
  2. L'ajouter à l'ExternalSecret concerné dans
     `platform-secrets/templates/externalsecrets.yaml`.
  3. Relancer le playbook 05. Seule la nouvelle clé est créée.
- **Supprimer un cluster.** Le job `vault-cleanup` retire l'auth, les
  policies et les rôles, purge `devver-infra-deployment/<org>/<env>`
  (`delete_all_versions`) et tous les chemins de `kubernetes-cluster/<org>/<env>/`,
  clients compris, **toutes versions comprises**. Ces secrets ne sont pas
  récupérables ensuite : à exporter avant si besoin.

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
