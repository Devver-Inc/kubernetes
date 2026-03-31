# external-dns

Configuration d'ExternalDNS pour la synchronisation automatique des enregistrements DNS Cloudflare à partir des ressources Kubernetes (Ingress et Service).

## Fichiers

| Fichier | Description |
|---|---|
| `external-dns-values.yaml` | Valeurs Helm pour ExternalDNS (provider Cloudflare) |
| `test-dep.yaml` | Déploiement de test |

## Fonctionnement

ExternalDNS surveille les ressources `Ingress` et `Service` du cluster. Dès qu'un Ingress avec un hostname est créé ou modifié, ExternalDNS crée ou met à jour automatiquement l'enregistrement DNS correspondant sur Cloudflare.

Cela élimine la gestion manuelle des entrées DNS lors des déploiements.

## Installation

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm install external-dns external-dns/external-dns -n external-dns --create-namespace \
  -f external-dns-values.yaml
```

## Prérequis

Un secret Kubernetes contenant le token API Cloudflare doit être présent dans le namespace `external-dns` (référencé dans `external-dns-values.yaml`).
