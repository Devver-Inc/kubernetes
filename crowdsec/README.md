# CrowdSec

Configuration du moteur de sécurité CrowdSec pour la détection d'intrusion sur le cluster Kubernetes.

## Fichiers

| Fichier | Description |
|---|---|
| `namespace.yaml` | Namespace dédié `crowdsec` |
| `values.yaml` | Valeurs Helm pour l'agent CrowdSec |

## Fonctionnement

CrowdSec analyse en temps réel les logs de Traefik pour détecter les comportements malveillants (brute force, scan de ports, etc.). Les IPs identifiées comme malveillantes peuvent être bloquées directement au niveau de Traefik via le bouncer CrowdSec.

## Installation

```bash
# Créer le namespace
kubectl apply -f namespace.yaml

# Installer CrowdSec via Helm
helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm install crowdsec crowdsec/crowdsec -n crowdsec -f values.yaml
```

## Configuration

Le fichier `values.yaml` configure l'agent pour surveiller les pods Traefik. Adapter les collections et parsers selon les besoins (ex : `crowdsecurity/traefik`).
