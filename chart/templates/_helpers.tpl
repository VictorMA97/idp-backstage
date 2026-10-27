{{- define "backstage.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ required "image.tag o image.digest son obligatorios" .Values.image.tag }}
{{- end -}}
{{- end -}}

{{- define "backstage.labels" -}}
app.kubernetes.io/part-of: idp
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
