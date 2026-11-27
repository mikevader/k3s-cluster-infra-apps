{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "apps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "apps.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "apps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "apps.labels" -}}
helm.sh/chart: {{ include "apps.chart" . }}
{{ include "apps.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "apps.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apps.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "apps.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "apps.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Replace [@, &] sign in email
*/}}
{{- define "apps.responsible" -}}
{{ .Values.responsible | replace "@" "__at__" | replace "&" "__and__" }}
{{- end -}}

{{/*
Resolve the onRemoval mode for one application.
Precedence: application `onRemoval` > group/chart `onRemoval` > "confirm".
Usage: include "apps.onRemoval" (dict "app" $value "root" $)
*/}}
{{- define "apps.onRemoval" -}}
{{- $mode := default "confirm" .root.Values.onRemoval -}}
{{- if and .app .app.onRemoval -}}
{{- $mode = .app.onRemoval -}}
{{- end -}}
{{- if not (has $mode (list "delete" "confirm" "preserve")) -}}
{{- fail (printf "onRemoval must be one of delete, confirm, preserve (got %q)" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/*
Argo CD sync-options value for an onRemoval mode; empty for "delete".
Usage: include "apps.onRemovalSyncOptions" "confirm"
*/}}
{{- define "apps.onRemovalSyncOptions" -}}
{{- if eq . "confirm" -}}
Prune=confirm,Delete=confirm
{{- else if eq . "preserve" -}}
Prune=false,Delete=false
{{- end -}}
{{- end -}}

{{/*
Overlay one map onto another, recursing into nested maps. Unlike mergeOverwrite, values from
`over` always win, including false, 0 and empty lists. Returns YAML.
Usage: include "apps.overlay" (dict "base" $groupValue "over" $appValue) | fromYaml
*/}}
{{- define "apps.overlay" -}}
{{- $base := deepCopy (default dict .base) -}}
{{- range $k, $v := (default dict .over) -}}
{{- if and (kindIs "map" $v) (kindIs "map" (get $base $k)) -}}
{{- $_ := set $base $k (include "apps.overlay" (dict "base" (get $base $k) "over" $v) | fromYaml) -}}
{{- else -}}
{{- $_ := set $base $k $v -}}
{{- end -}}
{{- end -}}
{{- toYaml $base -}}
{{- end -}}

{{/*
Group setting `key` with the application's `key` overlaid. Returns YAML.
Usage: include "apps.appSetting" (dict "key" "resourceQuota" "app" $value "root" $) | fromYaml
*/}}
{{- define "apps.appSetting" -}}
{{- $over := dict -}}
{{- if .app -}}
{{- $over = default dict (get .app .key) -}}
{{- end -}}
{{- include "apps.overlay" (dict "base" (get .root.Values .key) "over" $over) -}}
{{- end -}}
