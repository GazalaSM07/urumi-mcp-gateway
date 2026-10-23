$ErrorActionPreference = 'Stop'
$clusterName = if ($env:KIND_CLUSTER_NAME) { $env:KIND_CLUSTER_NAME } else { 'urumi' }
$images = @(
  @{ Name = 'urumi-gateway:dev-upstream-isolation'; Path = 'backend' },
  @{ Name = 'urumi-dashboard:dev'; Path = 'dashboard' },
  @{ Name = 'urumi-woo-mcp:dev'; Path = 'services/woo-mcp' },
  @{ Name = 'urumi-demo-mcp:dev'; Path = 'services/demo-mcp' },
  @{ Name = 'urumi-wordpress:dev'; Path = 'store' }
)
foreach ($image in $images) { docker build -t $image.Name $image.Path }
kind load docker-image urumi-gateway:dev-upstream-isolation urumi-dashboard:dev urumi-woo-mcp:dev urumi-demo-mcp:dev urumi-wordpress:dev --name $clusterName
