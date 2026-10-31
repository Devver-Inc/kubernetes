{{/* Identifiant du cluster : <org>-<env> */}}
{{- define "root.clusterId" -}}
{{- $org := required "cluster.org est requis" .Values.cluster.org -}}
{{- $env := required "cluster.env est requis" .Values.cluster.env -}}
{{- if not (has $env (list "prod" "staging" "dev")) -}}
{{- fail (printf "cluster.env=%q : prod, staging ou dev attendu" $env) -}}
{{- end -}}
{{- printf "%s-%s" $org $env -}}
{{- end }}

{{- define "root.domain" -}}
{{- required "cluster.domain est requis (<org>-<env>.devver.app)" .Values.cluster.domain -}}
{{- end }}

{{/* StorageClass du partage NFS du cluster */}}
{{- define "root.storageClass" -}}
{{- printf "nfs-%s" (include "root.clusterId" .) -}}
{{- end }}

{{/*
syncPolicy commune. Usage : include "root.syncPolicy" (dict "prune" true "opts" (list "ServerSideApply=true"))
*/}}
{{- define "root.syncPolicy" -}}
syncPolicy:
  automated:
    prune: {{ if hasKey . "prune" }}{{ .prune }}{{ else }}true{{ end }}
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    {{- range .opts }}
    - {{ . }}
    {{- end }}
  retry:
    limit: 10
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 5m
{{- end }}

{{/*
En-tête commun des Applications de la plateforme.
nonBlocking=true : annotation devver.app/non-blocking — l'Application garde
son vrai état dans ArgoCD, mais n'empêche pas les vagues suivantes (contrôle
de santé des Applications, Application "argocd"). Réservé aux composants dont
l'échec ne doit pas geler le cluster (ex: backend en attente de configuration).
*/}}
{{- define "root.appMeta" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
    {{- if .nonBlocking }}
    devver.app/non-blocking: "true"
    {{- end }}
{{- end }}

{{/*
Application d'un composant de la stack (chart local du repo kubernetes, valeurs
domain / dnsTarget / namespace.create / storageClass).
Usage : include "root.stackApp" (dict "ctx" $ "name" "minio" "wave" "2"
          "path" "minio" "namespace" "devver-minio" "storage" true "extra" (dict ...))
storage=true : composant avec PVC -> storageClass du cluster et prune=false
(une erreur dans git ne doit jamais supprimer un volume).
*/}}
{{- define "root.stackApp" -}}
{{- $ := .ctx -}}
{{ include "root.appMeta" (dict "name" .name "wave" .wave "nonBlocking" .nonBlocking) }}
spec:
  project: platform
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  source:
    repoURL: {{ $.Values.git.kubernetes.repoURL }}
    targetRevision: {{ $.Values.git.kubernetes.revision }}
    path: {{ .path }}
    helm:
      valuesObject:
        domain: {{ include "root.domain" $ }}
        dnsTarget: {{ $.Values.dnsTarget | quote }}
        namespace:
          create: false
        {{- if .storage }}
        storageClass: {{ include "root.storageClass" $ }}
        {{- end }}
        {{- with .extra }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
  {{- include "root.syncPolicy" (dict "prune" (not .storage) "opts" (list)) | nindent 2 }}
{{- end }}
