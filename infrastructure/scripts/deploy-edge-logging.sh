#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $*"
}

# Get Loki service IP from hub cluster
get_loki_ip() {
    kubectl --context kind-macula-hub get svc loki -n monitoring -o jsonpath='{.spec.clusterIP}'
}

# Deploy Fluent Bit to an edge cluster
deploy_to_edge() {
    local edge=$1
    local loki_host=$2
    local cluster_name=$3

    log_step "Deploying Fluent Bit to ${edge}..."

    # Create monitoring namespace
    kubectl --context kind-macula-${edge} create namespace monitoring --dry-run=client -o yaml | \
        kubectl --context kind-macula-${edge} apply -f -

    # Deploy Fluent Bit with edge-specific configuration
    cat <<EOF | kubectl --context kind-macula-${edge} apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluent-bit-read
rules:
- apiGroups: [""]
  resources:
  - namespaces
  - pods
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fluent-bit-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: fluent-bit-read
subjects:
- kind: ServiceAccount
  name: fluent-bit
  namespace: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: monitoring
  labels:
    app: fluent-bit
data:
  fluent-bit.conf: |
    [SERVICE]
        Daemon Off
        Flush 1
        Log_Level info
        Parsers_File parsers.conf
        Parsers_File custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
        Health_Check On

    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        multiline.parser docker, cri
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On

    [FILTER]
        Name kubernetes
        Match kube.*
        Kube_URL https://kubernetes.default.svc:443
        Kube_CA_File /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File /var/run/secrets/kubernetes.io/serviceaccount/token
        Kube_Tag_Prefix kube.var.log.containers.
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On
        Labels On
        Annotations Off

    [OUTPUT]
        Name loki
        Match kube.*
        Host ${loki_host}
        Port 3100
        Labels job=fluentbit, cluster=${cluster_name}
        Label_keys \$kubernetes['namespace_name'],\$kubernetes['pod_name'],\$kubernetes['container_name']
        Auto_Kubernetes_Labels On

  parsers.conf: |
    [PARSER]
        Name   docker
        Format json
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z

    [PARSER]
        Name   cri
        Format regex
        Regex ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z

  custom_parsers.conf: |
    [MULTILINE_PARSER]
        Name multiline-regex
        Type regex
        Flush_timeout 1000
        Rule "start_state" "/(\d+\-\d+\-\d+ \d+\:\d+\:\d+\.\d+)/" "cont"
        Rule "cont" "/^\s+at.*/" "cont"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: monitoring
  labels:
    app: fluent-bit
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:2.2.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 2020
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          limits:
            memory: 128Mi
            cpu: 200m
          requests:
            memory: 64Mi
            cpu: 50m
        volumeMounts:
        - name: config
          mountPath: /fluent-bit/etc/
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: fluent-bit-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
EOF

    log_info "✓ Fluent Bit deployed to ${edge}"
}

main() {
    echo
    log_info "========================================"
    log_info "Deploy Fluent Bit to Edge Clusters"
    log_info "========================================"
    echo

    # Get Loki service IP (NodePort on hub)
    log_step "Getting Loki service endpoint on hub..."
    loki_ip="172.20.0.2"  # Hub cluster IP
    log_info "Loki endpoint: http://${loki_ip}:30100"
    echo

    # Deploy to each edge cluster
    for edge_num in 01 02 03 04; do
        deploy_to_edge "edge-${edge_num}" "${loki_ip}" "macula-edge-${edge_num}"
        echo
    done

    log_info "========================================"
    log_info "✓ Fluent Bit deployment complete!"
    log_info "========================================"
    echo
    log_info "Logs from all edge clusters will now be forwarded to Loki on the hub."
    log_info "View logs in Grafana: http://analytics.macula.local:8080/explore"
    echo
}

main "$@"
