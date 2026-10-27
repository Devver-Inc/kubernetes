{{/*
Fullname : nomorga-nomprojet
*/}}
{{- define "mongo-template.fullname" -}}
{{- printf "%s-%s" (lower .Values.organization.name) (lower .Values.project.name) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Nom du déploiement MongoDB : nomorga-nomprojet-mongo
*/}}
{{- define "mongo-template.mongoName" -}}
{{- printf "%s-mongo" (include "mongo-template.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace : nomorga-nomprojet
*/}}
{{- define "mongo-template.namespace" -}}
{{- printf "%s-%s" (lower .Values.organization.name) (lower .Values.project.name) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "mongo-template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongo-template.labels" -}}
helm.sh/chart: {{ include "mongo-template.chart" . }}
app.kubernetes.io/name: {{ include "mongo-template.mongoName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
organization: {{ .Values.organization.name }}
project: {{ .Values.project.name }}
{{- with .Values.labels }}
{{- range $key, $value := . }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mongo-template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongo-template.mongoName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Chemin Vault (relatif au mount KV) : <org>/<env>/clients/<namespace>
*/}}
{{- define "mongo-template.vaultPath" -}}
{{- $org := required "cluster.org est requis quand secrets.enabled=true" .Values.cluster.org -}}
{{- $env := required "cluster.env est requis quand secrets.enabled=true" .Values.cluster.env -}}
{{- printf "%s/%s/clients/%s" $org $env (include "mongo-template.namespace" .) -}}
{{- end }}

{{/* Mount de l'auth Kubernetes Vault : k8s-<org>-<env> par défaut */}}
{{- define "mongo-template.vaultAuthMount" -}}
{{- default (printf "k8s-%s-%s" .Values.cluster.org .Values.cluster.env) .Values.secrets.vault.authMount -}}
{{- end }}

{{/*
Garde-fou Vault (template ESO v2, dans target.template.metadata.annotations) :
échoue si une valeur lue dans Vault est vide ou vaut CHANGEME. ESO ne crée /
ne modifie alors pas le Secret : le pod ne démarre pas tant que la valeur
n'est pas renseignée (même règle que le chart platform-secrets).
*/}}
{{- define "mongo-template.vaultCheck" -}}
devver.app/vault-check: {{ `{{ range $k, $v := . }}{{ if or (eq (trim $v) "") (eq (upper (trim $v)) "CHANGEME") }}{{ fail (printf "cle %s vide ou CHANGEME dans Vault" $k) }}{{ end }}{{ end }}ok` | squote }}
{{- end }}
