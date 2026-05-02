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
