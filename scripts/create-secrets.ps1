$ErrorActionPreference = 'Stop'

function Convert-SecureToPlain([securestring]$Value) {
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function New-RandomBase64([int]$Length = 32) {
  $bytes = [byte[]]::new($Length)
  $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $generator.GetBytes($bytes) }
  finally { $generator.Dispose() }
  return [Convert]::ToBase64String($bytes)
}

$adminPassword = Convert-SecureToPlain (Read-Host 'Choose the WordPress and dashboard admin password' -AsSecureString)
if ($adminPassword.Length -lt 12) { throw 'Use an admin password of at least 12 characters.' }
$fernetKey = (New-RandomBase64 32).Replace('+','-').Replace('/','_')
$dbPassword = New-RandomBase64 32
$dbRootPassword = New-RandomBase64 32
$llmSecure = Read-Host 'Optional OpenAI-compatible API key (press Enter to skip)' -AsSecureString
$llmKey = Convert-SecureToPlain $llmSecure

kubectl create namespace urumi --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Could not create namespace urumi.' }

$gatewayArgs = @('create','secret','generic','gateway-secrets','-n','urumi',"--from-literal=ADMIN_PASSWORD=$adminPassword", "--from-literal=FERNET_KEY=$fernetKey",'--dry-run=client','-o','yaml')
if ($llmKey) { $gatewayArgs += "--from-literal=OPENAI_API_KEY=$llmKey" }
& kubectl @gatewayArgs | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Could not create gateway-secrets.' }

$wordpressArgs = @('create','secret','generic','wordpress-secrets','-n','urumi',"--from-literal=DB_PASSWORD=$dbPassword", "--from-literal=DB_ROOT_PASSWORD=$dbRootPassword", "--from-literal=WP_ADMIN_PASSWORD=$adminPassword",'--from-literal=WP_ADMIN_USER=urumi-admin','--from-literal=WP_ADMIN_EMAIL=admin@urumi.local','--dry-run=client','-o','yaml')
& kubectl @wordpressArgs | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Could not create wordpress-secrets.' }
Write-Host 'Created gateway-secrets and wordpress-secrets in namespace urumi.'
Write-Host 'The WooCommerce API Secret is created after the store is running and its REST key has been generated.'
