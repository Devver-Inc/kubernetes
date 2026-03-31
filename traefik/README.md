# Traefik

Configuration de Traefik comme reverse proxy et ingress controller du cluster, avec MetalLB pour l'attribution d'IP externe.

## Fichiers

| Fichier | Description |
|---|---|
| `metallb-pool.yaml` | Pool d'adresses IP MetalLB pour les services `LoadBalancer` |
| `traefik-values.yaml` | Valeurs Helm Traefik (port 8443 websecure, ingressClass `traefik`) |

## Fonctionnement

MetalLB attribue une IP externe (LoadBalancer) au service Traefik. Traefik prend ensuite en charge le routage HTTP/HTTPS vers les services du cluster à partir des ressources `Ingress`.

Le TLS est géré automatiquement via cert-manager (Let's Encrypt).

## Installation

```bash
# Installer MetalLB
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace

# Configurer le pool d'IPs
kubectl apply -f metallb-pool.yaml

# Installer Traefik
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik -n traefik --create-namespace \
  -f traefik-values.yaml
```

## Notes

- Traefik doit être installé avant cert-manager et external-dns car ces composants dépendent de la présence de l'ingress controller.
- Le port websecure est configuré sur `8443` (à adapter selon l'exposition réseau souhaitée).
