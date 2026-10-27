{{/*
Expand the name of the chart.
*/}}
{{- define "app-template.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
Create a default fully qualified app name.
*/}}
{{- define "app-template.fullname" -}}
{{- printf "%s-%s" .Values.organization.name .Values.project.name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app-template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
{{/*
Common labels
*/}}
{{- define "app-template.labels" -}}
helm.sh/chart: "{{ include "app-template.chart" . }}"
{{- include "app-template.selectorLabels" . | nindent 0 }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: "{{ .Chart.AppVersion }}"
{{- end }}
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
organization: "{{ .Values.organization.name }}"
project: "{{ .Values.project.name }}"
{{- with .Values.labels }}
{{- range $key, $value := . }}
{{ $key }}: "{{ $value }}"
{{- end }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app-template.selectorLabels" -}}
app.kubernetes.io/name: "{{ include "app-template.name" . }}"
app.kubernetes.io/instance: "{{ .Release.Name }}"
{{- end }}
{{/*
Create the namespace name
*/}}
{{- define "app-template.namespace" -}}
{{- printf "%s-%s" (lower .Values.organization.name) (lower .Values.project.name) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
Create the full hostname for the ingress
*/}}
{{- define "app-template.hostname" -}}
{{- printf "%s.%s.%s" .Values.organization.name .Values.project.name .Values.organization.domain }}
{{- end }}
{{/*
Create the PVC name
*/}}
{{- define "app-template.pvcName" -}}
{{- $ctx := .context }}
{{- if not $ctx }}
{{- $ctx = . }}
{{- end }}
{{- $name := .name | default "data" }}
{{- printf "%s-%s" (include "app-template.fullname" $ctx) $name | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{/* Explicit PVC name for `app` */}}
{{- define "app-template.pvcNameApp" -}}
{{- printf "%s-app" (include "app-template.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{/* Explicit PVC name for `root` */}}
{{- define "app-template.pvcNameRoot" -}}
{{- printf "%s-root" (include "app-template.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{/*
Chemin Vault (relatif au mount KV) des secrets de ce namespace :
<org>/<env>/clients/<namespace>
*/}}
{{- define "app-template.vaultPath" -}}
{{- $org := required "cluster.org est requis quand secrets.enabled=true" .Values.cluster.org -}}
{{- $env := required "cluster.env est requis quand secrets.enabled=true" .Values.cluster.env -}}
{{- printf "%s/%s/clients/%s" $org $env (include "app-template.namespace" .) -}}
{{- end }}
{{/* Mount de l'auth Kubernetes Vault : k8s-<org>-<env> par défaut */}}
{{- define "app-template.vaultAuthMount" -}}
{{- default (printf "k8s-%s-%s" .Values.cluster.org .Values.cluster.env) .Values.secrets.vault.authMount -}}
{{- end }}

{{/*
Garde-fou Vault (template ESO v2, dans target.template.metadata.annotations) :
échoue si une valeur lue dans Vault est vide ou vaut CHANGEME. ESO ne crée /
ne modifie alors pas le Secret : le pod ne démarre pas tant que la valeur
n'est pas renseignée (même règle que le chart platform-secrets).
*/}}
{{- define "app-template.vaultCheck" -}}
devver.app/vault-check: {{ `{{ range $k, $v := . }}{{ if or (eq (trim $v) "") (eq (upper (trim $v)) "CHANGEME") }}{{ fail (printf "cle %s vide ou CHANGEME dans Vault" $k) }}{{ end }}{{ end }}ok` | squote }}
{{- end }}
