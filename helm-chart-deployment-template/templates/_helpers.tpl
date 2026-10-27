{{- define "app-template.name" -}}
deploy-agent
{{- end }}

{{- define "app-template.fullname" -}}
deploy-agent
{{- end }}

{{- define "app-template.namespace" -}}
{{- printf "p-%s" (required "project.id est obligatoire" .Values.project.id) }}
{{- end }}

{{- define "app-template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app-template.labels" -}}
helm.sh/chart: "{{ include "app-template.chart" . }}"
{{ include "app-template.selectorLabels" . }}
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
devver.app/project-id: "{{ .Values.project.id }}"
{{- with .Values.labels }}
{{- range $key, $value := . }}
{{ $key }}: "{{ $value }}"
{{- end }}
{{- end }}
{{- end }}

{{- define "app-template.selectorLabels" -}}
app.kubernetes.io/name: "deploy-agent"
app.kubernetes.io/instance: "{{ .Release.Name }}"
{{- end }}

{{- define "app-template.pvcNameApp" -}}
deploy-agent-app
{{- end }}

{{- define "app-template.pvcNameRoot" -}}
deploy-agent-root
{{- end }}
