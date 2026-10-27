# cert-manager

Configuration du `ClusterIssuer` Let's Encrypt pour l'émission automatique de certificats TLS via le challenge DNS01 avec Cloudflare.

## Fichiers

| Fichier | Description |
|---|---|
| `clusterissuer.yaml` | ClusterIssuer Let's Encrypt (production) |

## Fonctionnement

cert-manager utilise le challenge **DNS01** via l'API Cloudflare pour valider la propriété du domaine et émettre des certificats Let's Encrypt. Cette méthode permet d'obtenir des certificats wildcard et fonctionne sans exposition HTTP.

## Installation

```bash
# Installer cert-manager via Helm
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set installCRDs=true

# Le Secret cloudflare-dns (token API Cloudflare) n'est plus dans ce dossier :
# il est synchronisé depuis Vault (kubernetes-cluster/<org>/<env>/cloudflare)
# par le chart platform-secrets — voir docs/vault-nouveau-cluster.md

# Créer le ClusterIssuer
kubectl apply -f clusterissuer.yaml
```

## Utilisation

Une fois le ClusterIssuer créé, les Ingress peuvent demander un certificat automatiquement via l'annotation :

```yaml
cert-manager.io/cluster-issuer: letsencrypt-prod
```
