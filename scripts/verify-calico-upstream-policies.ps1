$ErrorActionPreference = 'Stop'

$node = 'urumi-policy-check-control-plane'
$namespace = 'calico-policy-test'

function Invoke-ClusterKubectl {
    param([Parameter(Mandatory)][string[]]$KubectlArgs)
    & docker exec $node kubectl --kubeconfig=/etc/kubernetes/admin.conf @KubectlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl command failed (exit $LASTEXITCODE): $($KubectlArgs -join ' ')"
    }
}

$manifest = @'
apiVersion: v1
kind: Pod
metadata:
  name: woo-policy-target
  namespace: calico-policy-test
  labels: {app: woo-mcp}
spec:
  containers:
    - name: server
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /www && echo woo-ok > /www/index.html && exec httpd -f -p 8001 -h /www"]
      ports: [{containerPort: 8001}]
---
apiVersion: v1
kind: Service
metadata: {name: woo-policy-target, namespace: calico-policy-test}
spec:
  selector: {app: woo-mcp}
  ports: [{port: 8001, targetPort: 8001}]
---
apiVersion: v1
kind: Pod
metadata:
  name: inventory-policy-target
  namespace: calico-policy-test
  labels: {app: inventory-mcp}
spec:
  containers:
    - name: server
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /www && echo inventory-ok > /www/index.html && exec httpd -f -p 8002 -h /www"]
      ports: [{containerPort: 8002}]
---
apiVersion: v1
kind: Service
metadata: {name: inventory-policy-target, namespace: calico-policy-test}
spec:
  selector: {app: inventory-mcp}
  ports: [{port: 8002, targetPort: 8002}]
---
apiVersion: v1
kind: Pod
metadata:
  name: metrics-policy-target
  namespace: calico-policy-test
  labels: {app: metrics-mcp}
spec:
  containers:
    - name: server
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /www && echo metrics-ok > /www/index.html && exec httpd -f -p 8002 -h /www"]
      ports: [{containerPort: 8002}]
---
apiVersion: v1
kind: Service
metadata: {name: metrics-policy-target, namespace: calico-policy-test}
spec:
  selector: {app: metrics-mcp}
  ports: [{port: 8002, targetPort: 8002}]
---
apiVersion: v1
kind: Pod
metadata:
  name: gateway-policy-client
  namespace: calico-policy-test
  labels: {app: gateway}
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: peer-policy-client
  namespace: calico-policy-test
  labels: {app: peer}
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: woo-mcp-gateway-only, namespace: calico-policy-test}
spec:
  podSelector: {matchLabels: {app: woo-mcp}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {app: gateway}}}]
      ports: [{protocol: TCP, port: 8001}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: inventory-mcp-gateway-only, namespace: calico-policy-test}
spec:
  podSelector: {matchLabels: {app: inventory-mcp}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {app: gateway}}}]
      ports: [{protocol: TCP, port: 8002}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: metrics-mcp-gateway-only, namespace: calico-policy-test}
spec:
  podSelector: {matchLabels: {app: metrics-mcp}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {app: gateway}}}]
      ports: [{protocol: TCP, port: 8002}]
'@

$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifest))
$applyCommand = "printf '%s' '$encoded' | base64 -d > /tmp/urumi-policy-verification.yaml && kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/urumi-policy-verification.yaml"
& docker exec $node sh -c $applyCommand
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the temporary Calico policy verification resources.' }

Invoke-ClusterKubectl @('wait', '--for=condition=Ready', 'pod/woo-policy-target', 'pod/inventory-policy-target', 'pod/metrics-policy-target', 'pod/gateway-policy-client', 'pod/peer-policy-client', "--namespace=$namespace", '--timeout=180s')

$checks = @(
    @{ Client = 'gateway-policy-client'; Service = 'woo-policy-target'; Port = '8001'; Expected = 'woo-ok' },
    @{ Client = 'gateway-policy-client'; Service = 'inventory-policy-target'; Port = '8002'; Expected = 'inventory-ok' },
    @{ Client = 'gateway-policy-client'; Service = 'metrics-policy-target'; Port = '8002'; Expected = 'metrics-ok' }
)

foreach ($check in $checks) {
    $result = & docker exec $node kubectl --kubeconfig=/etc/kubernetes/admin.conf exec $check.Client "--namespace=$namespace" -- wget -T 5 -qO- "http://$($check.Service):$($check.Port)"
    if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -notmatch $check.Expected) {
        throw "FAIL: gateway could not reach $($check.Service):$($check.Port)."
    }
    Write-Host "PASS: gateway can reach $($check.Service):$($check.Port)."
}

foreach ($check in $checks) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # A timeout is the expected denial signal. Keep native stderr from
        # turning that expected non-zero exit into a terminating PowerShell error.
        $ErrorActionPreference = 'Continue'
        $null = & docker exec $node kubectl --kubeconfig=/etc/kubernetes/admin.conf exec peer-policy-client "--namespace=$namespace" -- wget -T 5 -qO- "http://$($check.Service):$($check.Port)" 2>&1
        $peerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($peerExitCode -eq 0) {
        throw "FAIL: non-gateway peer unexpectedly reached $($check.Service):$($check.Port)."
    }
    Write-Host "PASS: non-gateway peer is blocked from $($check.Service):$($check.Port)."
}

Write-Host 'All three gateway-only NetworkPolicy checks passed. Temporary test resources remain in calico-policy-test; nothing was deleted.'
