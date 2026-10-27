{{- define "mongo-template.namespace" -}}
{{- printf "p-%s" (required "project.id est obligatoire" .Values.project.id) }}
{{- end }}

{{- define "mongo-template.fullname" -}}
{{- include "mongo-template.namespace" . }}
{{- end }}

{{- define "mongo-template.mongoName" -}}
{{- printf "%s-mongo" (include "mongo-template.namespace" .) }}
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
devver.app/project-id: {{ .Values.project.id | quote }}
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
