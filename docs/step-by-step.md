# Step-by-step build and demo guide

This guide follows the order that minimizes debugging: first create the cluster and store, then connect the custom adapter, then add the gateway/dashboard, and finally rehearse the two-user flow. The core implementation is in this repo. Read the source files as you go so you can explain what each part does in the interview.

## 1. Understand the system before running it

The request path is:

1. A browser or MCP client sends a request to the dashboard hostname.
2. Dashboard nginx forwards `/api/*` and `/mcp` to the gateway Service.
3. The gateway checks the caller's bearer API key against a SHA-256 hash in SQLite.
4. The gateway discovers tools from each enabled upstream and returns the namespaced tool list.
5. For a tool call, the gateway chooses the upstream from the prefix in the tool name, attaches only that upstream's stored credential, and calls its MCP endpoint.
6. WooCommerce MCP translates its five tools into WooCommerce REST API calls. WordPress reads/writes MySQL; the result returns through the same path.
7. The gateway records who called which tool, the time, duration and outcome.

The browser never talks directly to WooCommerce MCP. The WooCommerce MCP endpoint, demo MCP endpoints, gateway API and MySQL Services are internal ClusterIP Services. Ingress exposes only the storefront and dashboard. The Helm chart adds a NetworkPolicy that allows WooCommerce MCP ingress only from the gateway. The local cluster uses Calico, and the guide includes a live allowed/blocked connectivity check.

## 2. Prepare a local Kubernetes cluster

Install Docker Desktop, Kind, kubectl and Helm 3. In the repo directory, create a cluster named `urumi` using `kind-calico.yaml`:

```powershell
kind create cluster --name urumi --config kind-calico.yaml
```

`kind-calico.yaml` maps host ports 80 and 443 into the Kind control plane and disables Kind's default `kindnet` CNI. Calico must be installed on this fresh cluster so its NetworkPolicy is enforced. Install Calico 3.33 (the custom resource uses the same `192.168.0.0/16` pod range configured in `kind-calico.yaml`):

```powershell
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/v3_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
kubectl wait --for=condition=Available --timeout=180s deployment/tigera-operator -n tigera-operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/custom-resources.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get pods -A | findstr /i "calico tigera"
```

Wait until Calico pods are `Running`. Then install a local-path storage provisioner and ingress-nginx:

```powershell
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
```

The storage provisioner turns PVC requests into local persistent volumes. The ingress controller routes HTTP hostnames to Kubernetes Services. Helm is required by the brief and installs all app resources from `helm/urumi/`.

## 3. Create credentials as Kubernetes Secrets

Run:

```powershell
.\scripts\create-secrets.ps1
```

The script asks for the first WordPress/dashboard admin password, randomly creates MySQL passwords and a Fernet key, then creates two Secrets in namespace `urumi`:

- `gateway-secrets`: admin password, `FERNET_KEY`, and an optional LLM key.
- `wordpress-secrets`: database passwords and the WordPress admin username/password.

The Fernet key encrypts upstream credentials saved by the gateway. The LLM key is needed only if you want chat-agent answers; the store and MCP gateway can otherwise be exercised directly. Credentials are not stored in Helm values or source files. Kubernetes Secrets are only base64-encoded by default, so use encryption at rest or an external secret manager on a real VPS.

## 4. Build and load the container images

Run:

```powershell
.\scripts\build-local.ps1
```

This builds the gateway, dashboard, WooCommerce adapter, demo MCP server and custom WordPress image, then loads them into the Kind cluster named `urumi`. To use another cluster name, set `$env:KIND_CLUSTER_NAME` before running the script. The custom WordPress image includes WP-CLI and the pinned WooCommerce plugin. Docker needs network access during this step to download base images/dependencies.

## 5. Deploy all services with Helm

Run:

```powershell
helm upgrade --install urumi .\helm\urumi -n urumi --create-namespace -f .\helm\urumi\values-local.yaml
kubectl -n urumi get pods,svc,ingress,pvc
kubectl -n urumi rollout status statefulset/mysql
kubectl -n urumi rollout status deployment/wordpress
```

The chart installs the `woo-mcp-gateway-only` NetworkPolicy. Confirm the gateway can reach WooCommerce MCP (expected `200`) and the inventory pod is blocked (expected connection timeout):

```bash
kubectl -n urumi get networkpolicy
kubectl -n urumi exec deployment/gateway -- python -c 'import urllib.request; print(urllib.request.urlopen("http://woo-mcp:8001/healthz", timeout=5).status)'
kubectl -n urumi exec deployment/inventory-mcp -- python -c '
import socket, sys
try:
    socket.create_connection(("woo-mcp", 8001), timeout=3)
    print("UNEXPECTEDLY REACHABLE")
    sys.exit(1)
except TimeoutError:
    print("BLOCKED as expected")
'
```

The chart creates:

- A MySQL StatefulSet and PVC.
- A WordPress Deployment and PVC for site files/uploads.
- A gateway Deployment and PVC for SQLite state/audit history.
- WooCommerce, inventory and metrics MCP Deployments and internal Services.
- A dashboard Deployment and Services.
- Two Ingress rules, one per stable hostname.

Each workload has requests/limits plus readiness and liveness probes. The WooCommerce API Secret is optional during the first boot, so the storefront can initialize before its REST key has been created. Its tools return a credential setup error until that Secret is added.

## 6. Configure the local hostnames

Edit the Windows hosts file as Administrator and add:

```text
127.0.0.1 urumi.local dashboard.urumi.local
```

Open `http://urumi.local` and `http://dashboard.urumi.local`. If a page does not load, inspect the ingress controller and pod states before changing application code:

```powershell
kubectl -n ingress-nginx get pods
kubectl -n urumi get pods,ingress
```

## 7. Initialize WooCommerce and grant the adapter a scoped key

WordPress is bootstrapped from the Secret. Sign in at `http://urumi.local/wp-admin` with `admin@urumi.local` and the admin password you chose. Then:

1. Add a dedicated WordPress user with the **Shop manager** role. This avoids using the site owner for API calls.
2. Open **WooCommerce → Settings → Advanced → REST API** and create a key for that user.
3. Grant **Read/Write**, because the required demo creates products and reads/orders updates.
4. Put the key and secret into the Secret, then restart the adapter to refresh its environment:

   ```powershell
   kubectl -n urumi create secret generic woocommerce-api --from-literal=WC_CONSUMER_KEY='<consumer-key>' --from-literal=WC_CONSUMER_SECRET='<consumer-secret>' --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n urumi rollout restart deployment/woo-mcp
   ```

The WooCommerce adapter uses REST rather than WP-CLI for requests because REST is a stable, typed boundary for products and orders, and it exercises the store's normal authorization checks. The adapter's `main.py` defines the MCP tool schemas and translates arguments to WooCommerce endpoints. `list_orders` accepts `after`/`before`; `create_product` creates a published simple product. Since local REST runs over internal HTTP, the adapter signs OAuth 1.0a requests so the consumer secret itself is never put on the request.

## 8. Sign in, invite users and issue keys

The bootstrap admin is `admin@urumi.local`. On the dashboard:

1. Open **Team** and add two members using separate emails/passwords.
2. As an admin, issue a key for either member from the Team page, or sign in as that member and use **API keys → Generate API key**.
3. Copy the generated key immediately. The raw token is returned only once; the database stores its SHA-256 hash.
4. As the admin, use **API keys** to revoke any team's key. A member can revoke only their own keys.

The dashboard login is backed by a hashed session token in the same key table. Password hashes use PBKDF2. The admin's key is not forwarded upstream.

## 9. Understand the gateway and tool naming

The gateway stores the three initial upstream definitions in SQLite at first start:

- `woocommerce` → `http://woo-mcp:8001/mcp`
- `inventory` → `http://inventory-mcp:8002/mcp`
- `metrics` → `http://metrics-mcp:8003/mcp`

It initializes each server as an MCP client, remembers any returned MCP session ID, then calls `tools/list`. A public tool name is `<server>__<tool>`, so two servers may both have a tool called `search` without a collision. Calls are routed back to the matching upstream and the unprefixed name is sent to it. Each server call has a 5-second timeout; an unreachable server is reported independently and does not prevent tools from the other two from being listed.

Admins can add, edit, disable and remove upstreams from **Servers**. Public endpoints require HTTPS; only MCP services in the `urumi` namespace can use in-cluster HTTP. Static credentials are encrypted in the gateway's SQLite database and are never returned in dashboard JSON.

## 10. Exercise chat as User A

Sign in as member A and open **Chat**. Ask:

> Create a product named Round One Demo Mug for 499 INR with a short description.

The model receives the available JSON schemas, chooses `woocommerce__create_product`, the gateway audits the call, and the WooCommerce adapter creates the product over REST. Confirm it appears at `http://urumi.local`.

Add the product to cart and check out manually. Select cash on delivery and complete checkout. Sign into WordPress admin and confirm the order appears under WooCommerce → Orders. Return to Chat and ask:

> What orders came in today?

The chat loop supplies today's exact Asia/Kolkata store-local interval and expects a date-bounded call to `woocommerce__list_orders`. The answer should include the order you just placed. The tool call should appear in **Audit log** under A's email.

## 11. Connect User B through an external MCP client

Sign in as member B in a separate browser profile and create a fresh key. In MCP Inspector, choose Streamable HTTP, enter:

- URL: `http://dashboard.urumi.local/mcp`
- Header: `Authorization: Bearer <B's key>`

Initialize/list tools; verify WooCommerce, inventory and metrics tools all appear. Call `woocommerce__list_orders` with a day interval to match Chat's query. MCP Inspector has no natural-language prompt interface, so use an MCP-enabled AI client such as Claude Code or Cursor for the cross-server prompt: “Search inventory notes for the Round One Demo Mug, then get today's store metrics and summarize both results.” As an alternative live demonstration, sign in to dashboard Chat as B and submit that prompt; its calls use B's dashboard session and are audited as B. The gateway narrows this cross-server request to the inventory and metrics tools and returns their results even if the LLM stalls while composing its final text.

Revoke B's key from the admin dashboard. Call `tools/list` again; the gateway should reject it with HTTP 401. This is the key-revocation demonstration.

## 12. Demonstrate control and failure isolation

Disable `metrics` in the admin's **Servers** tab. Refresh MCP tools from the client and **Tools** in the dashboard: metrics tools should disappear, while WooCommerce and inventory remain. Re-enable metrics.

Delete the inventory pod:

```powershell
kubectl -n urumi delete pod -l app=inventory-mcp
```

During the short replacement window, refresh dashboard status. It should show inventory as `Unreachable`, while tools/calls from WooCommerce and metrics still work. Kubernetes restarts the pod; wait for it to become ready before continuing.

## 13. Prepare the production-like k3s version

Build/tag/push the same five images to a registry you control. Edit `helm/urumi/values-prod.yaml` with the image paths/tags and your real store/dashboard DNS names. Create the referenced Kubernetes Secrets in the `urumi` namespace; create a TLS secret or use cert-manager. Confirm the k3s StorageClass supports the requested PVC sizes. Then install the same chart:

```sh
helm upgrade --install urumi ./helm/urumi -n urumi --create-namespace -f ./helm/urumi/values-prod.yaml
```

The hostnames, scheme, ingress class, TLS, StorageClass, image registry, claim size and resource limits vary by values file. The Helm templates do not change. Use `helm history urumi -n urumi` to inspect releases and `helm rollback urumi <revision> -n urumi` to restore an earlier chart revision. Back up the store/database volumes before upgrades.

## 14. Record the demo and submit

Use the assignment's demo checklist: architecture, live checkout, User A chat, User B external MCP client, cross-upstream prompt, revocation, disablement, dead-upstream behavior, audit log, secrets/volumes/Ingress/probes/limits, MCP routing/session handling, threat model, and local-to-k3s values. Explain the exact source files you wrote and the tradeoffs in `docs/system-design.md` and `docs/threat-model.md`. Submit the demo video and GitHub repository through the form in the assignment. Do not submit until you have actually run the system and can explain the calls and resources yourself.

## 15. Troubleshooting starting points

- **Pods pending:** check PVCs and `kubectl -n urumi describe pvc`; verify the `local-path` provisioner is ready.
- **ImagePullBackOff:** rerun the local image build/load script and confirm Kind is named `urumi`.
- **WooCommerce tool errors:** verify the `woocommerce-api` Secret keys and restart `woo-mcp`.
- **Chat says LLM key missing:** add `OPENAI_API_KEY` to `gateway-secrets`, then restart `gateway`. A compatible local model can be configured through `LLM_BASE_URL` and `LLM_MODEL` values.
- **Hostname not resolving:** confirm the hosts-file entry, ingress-nginx pods and Kind port mappings.
- **Gateway state unexpectedly reset:** ensure the `gateway-data` PVC is bound and not removed between installs.
