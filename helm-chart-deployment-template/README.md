## Installation Helm

https://helm.sh/docs/intro/install

## Import de la configuration du cluster K8s
Importer la configuration du cluster avec la commande suivante:
```
export KUBECONFIG=/home/$HOME/backend-kubeconfig.yaml
```
Permet à Helm de se connecter au cluster pour appliquer les instructions.

## Créer un déploiement

Avec valeur par défaut (spécifié dans le values.yaml)

```
helm install NOM-DEPLOIEMENT ./helm-chart-deployment-template
```

En Spécifiant certaines valeurs personnalisées

```
helm install NOM-DEPLOIEMENT ./helm-chart-deployment-template 
--set project.name=mon-nom-de-projet
--set organization.name=nom-de-l'organisation
```

## Modifier un déploiement

  
Exemple Augmenter la RAM

```
helm upgrade NOM-DEPLOIEMENT ./helm-chart-deployment-template
--set resources.requests.memory=”256Mi”
--set resources.limits.memory=”256Mi”
```

## Supprimer un déploiement

```
helm uninstall nom-du deploiement-helm
```

## Lister les déploiements en cours

```
helm list
```

## Configuration d’un déploiement

Tous les paramètres configurables pour un déploiement se trouvent dans le fichier values.yaml du chart.

Voici un tableau récapitulatif de l'utilité de chacune

| organization.name                            | Nom de l’organisation                                                                                                                                  |
|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| project.name                                 | Nom du Projet                                                                                                                                          |
| container.image                              | Image du conteneur à déployer                                                                                                                          |
| resources.memory.requests (idem pour limits) | Taille de la mémoire à allouer<br />Indiquer l’unité (Mi Gi …)                                                                                         |
| resources.cpu.requests (idem pour limits)    | Unité en Millicore<br />Possibilité d’exprimer la valeur en entier : <br />1.5 pour 1,5 CPU<br />ou en milli (bien préciser le m)<br />1500m = 1,5 CPU |
| persistence.size                             | Taille du volume persistant en Gi                                                                                                                      |
| persistence.mounPath                         | Indiquer le répertoire à persister<br />exemple: /data                                                                                                 |
| replicaCount                                 | Possibilité de définir de la réplication de conteneur, dans ce cas indiquer le nombre                                                                  |

Pour les autres variables ne pas modifier

Pour la définition des ressources, définir les mêmes valeurs pour les limits que pour les requests.