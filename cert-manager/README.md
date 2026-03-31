# cert-manager

Configuration du `ClusterIssuer` Let's Encrypt pour l'émission automatique de certificats TLS via le challenge DNS01 avec Cloudflare.

## Fichiers

| Fichier | Description |
|---|---|
| `cloudflare-secret.yaml` | Secret contenant le token API Cloudflare |
| `clusterissuer.yaml` | ClusterIssuer Let's Encrypt (production) |

## Fonctionnement

cert-manager utilise le challenge **DNS01** via l'API Cloudflare pour valider la propriété du domaine et émettre des certificats Let's Encrypt. Cette méthode permet d'obtenir des certificats wildcard et fonctionne sans exposition HTTP.

## Installation

```bash
# Installer cert-manager via Helm
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set installCRDs=true

# Créer le secret Cloudflare (renseigner le token avant d'appliquer)
kubectl apply -f cloudflare-secret.yaml

# Créer le ClusterIssuer
kubectl apply -f clusterissuer.yaml
```

## Utilisation

Une fois le ClusterIssuer créé, les Ingress peuvent demander un certificat automatiquement via l'annotation :

```yaml
cert-manager.io/cluster-issuer: letsencrypt-prod
```
