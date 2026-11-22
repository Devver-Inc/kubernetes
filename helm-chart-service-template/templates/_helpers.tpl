{{- define "service-template.namespace" -}}
{{- printf "p-%s" (required "project.id est requis" .Values.project.id) -}}
{{- end }}

{{- define "service-template.name" -}}
{{- required "name est requis" .Values.name -}}
{{- end }}

{{- define "service-template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service-template.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "service-template.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "service-template.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
project: {{ .Values.project.id | quote }}
{{- range $key, $value := .Values.labels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}

{{/* Chemin Vault (relatif au mount KV) : <org>/<env>/clients/<namespace> */}}
{{- define "service-template.vaultPath" -}}
{{- $org := required "cluster.org est requis avec secretEnv.vaultKey" .Values.cluster.org -}}
{{- $env := required "cluster.env est requis avec secretEnv.vaultKey" .Values.cluster.env -}}
{{- printf "%s/%s/clients/%s" $org $env (include "service-template.namespace" .) -}}
{{- end }}

{{- define "service-template.vaultAuthMount" -}}
{{- default (printf "k8s-%s-%s" .Values.cluster.org .Values.cluster.env) .Values.secrets.vault.authMount -}}
{{- end }}

{{/*
Garde-fou Vault (template ESO v2) : échoue si une valeur lue est vide ou vaut
CHANGEME ; ESO ne crée alors pas le Secret et le pod ne démarre pas.
*/}}
{{- define "service-template.vaultCheck" -}}
devver.app/vault-check: {{ `{{ range $k, $v := . }}{{ if or (eq (trim $v) "") (eq (upper (trim $v)) "CHANGEME") }}{{ fail (printf "cle %s vide ou CHANGEME dans Vault" $k) }}{{ end }}{{ end }}ok` | squote }}
{{- end }}
