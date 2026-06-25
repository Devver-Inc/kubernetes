1 setup la backup côté prod avec sauvegarde du catalogue

Policy bacjup all namespace yaml +pvc

![alt text](image.png)

Backup catalogue

![alt text](image-1.png)


2 Cluster de restaure

On partira de la situation suivante ou on a deja un cluster pret a utiliser avec la stakc de base (longhorn traefik ...)

Kasten deja installer provisionnner nfs aussi

il faut apply le pv dr avec bon path
puis pvc dr


puis crée le profile slocation avec le bon path > kubectl get profile -n kasten-io -o yaml | grep -A20 "fileSystem\|pvcName\|path\|subPath"


faire le processus de restaure
![alt text](image-2.png)


on a tout on peut restaure modifier ingress si besoin


Exemple restauration logto qui a un pvc 
tout est fait depuis kasten
on desactive la resto des ingress que l'on adaptera et apply manuellement
il faudrait aussi modifier certaines env pour avoir le bon domaine
mais ici on veux juste voir si le pvc et bien remonté


après restoration
je retrouve bien les données dans logto
![alt text](image-3.png)