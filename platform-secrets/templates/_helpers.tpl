{{/* Préfixe des chemins Vault : <org>/<env> */}}
{{- define "platform-secrets.prefix" -}}
{{- $org := required "cluster.org est requis" .Values.cluster.org -}}
{{- $env := required "cluster.env est requis" .Values.cluster.env -}}
{{- if not (has $env (list "prod" "staging" "dev")) -}}
{{- fail (printf "cluster.env=%q : prod, staging ou dev attendu" $env) -}}
{{- end -}}
{{- printf "%s/%s" $org $env -}}
{{- end }}

{{/* Mount de l'auth Kubernetes : k8s-<org>-<env> par défaut */}}
{{- define "platform-secrets.authMount" -}}
{{- default (printf "k8s-%s-%s" .Values.cluster.org .Values.cluster.env) .Values.vault.authMount -}}
{{- end }}

{{- define "platform-secrets.labels" -}}
app.kubernetes.io/name: platform-secrets
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Provider Vault commun aux ClusterSecretStores.
Usage : include "platform-secrets.vaultProvider" (dict "ctx" $ "role" "eso-platform" "sa" "eso-platform")
*/}}
{{- define "platform-secrets.vaultProvider" -}}
{{- $ctx := .ctx -}}
vault:
  server: {{ $ctx.Values.vault.server | quote }}
  path: {{ $ctx.Values.vault.mount | quote }}
  version: v2
  {{- with $ctx.Values.vault.caProvider }}
  caProvider:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  auth:
    kubernetes:
      mountPath: {{ include "platform-secrets.authMount" $ctx | quote }}
      role: {{ .role | quote }}
      serviceAccountRef:
        name: {{ .sa | quote }}
        namespace: {{ $ctx.Values.esoNamespace | quote }}
{{- end }}

{{/*
Garde-fou commun à TOUS les ExternalSecrets (à inclure dans
target.template.metadata.annotations) : template ESO (moteur v2) qui échoue si
une valeur lue dans Vault est vide ou vaut CHANGEME (valeur initiale posée par
ansible/playbooks/05-vault-k8s.yml). En cas d'échec, ESO ne crée / ne modifie
PAS le Secret (ExternalSecret en SecretSyncedError avec le nom de la clé) :
un pod qui le référence ne démarre pas (CreateContainerConfigError), et
redémarre seul dès que la valeur est saisie. Un Secret déjà valide n'est
jamais écrasé par une valeur invalide.
Sans template.data, ESO garde toutes les clés lues (data / dataFrom).
*/}}
{{- define "platform-secrets.vaultCheck" -}}
devver.app/vault-check: {{ `{{ range $k, $v := . }}{{ if or (eq (trim $v) "") (eq (upper (trim $v)) "CHANGEME") }}{{ fail (printf "cle %s vide ou CHANGEME dans Vault : a saisir dans la console" $k) }}{{ end }}{{ end }}ok` | squote }}
{{- end }}
