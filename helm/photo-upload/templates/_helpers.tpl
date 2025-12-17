{{/*
Expand the name of the chart.
*/}}
{{- define "photo-upload.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "photo-upload.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "photo-upload.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "photo-upload.labels" -}}
helm.sh/chart: {{ include "photo-upload.chart" . }}
{{ include "photo-upload.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "photo-upload.selectorLabels" -}}
app.kubernetes.io/name: {{ include "photo-upload.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Backend specific labels
*/}}
{{- define "photo-upload.backend.labels" -}}
helm.sh/chart: {{ include "photo-upload.chart" . }}
{{ include "photo-upload.backend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Backend selector labels
*/}}
{{- define "photo-upload.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "photo-upload.name" . }}-backend
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Frontend specific labels
*/}}
{{- define "photo-upload.frontend.labels" -}}
helm.sh/chart: {{ include "photo-upload.chart" . }}
{{ include "photo-upload.frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "photo-upload.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "photo-upload.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "photo-upload.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "photo-upload.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Database host
*/}}
{{- define "photo-upload.database.host" -}}
{{- if .Values.database.external.enabled }}
{{- .Values.database.external.host }}
{{- end }}
{{- end }}

{{/*
Database port
*/}}
{{- define "photo-upload.database.port" -}}
{{- if .Values.database.external.enabled }}
{{- .Values.database.external.port }}
{{- end }}
{{- end }}

{{/*
Database name
*/}}
{{- define "photo-upload.database.name" -}}
{{- if .Values.database.external.enabled }}
{{- .Values.database.external.name }}
{{- end }}
{{- end }}

{{/*
Backend fullname
*/}}
{{- define "photo-upload.backend.fullname" -}}
{{- printf "%s-backend" (include "photo-upload.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Frontend fullname
*/}}
{{- define "photo-upload.frontend.fullname" -}}
{{- printf "%s-frontend" (include "photo-upload.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
