# Urumi team MCP gateway

Round 1 implementation: a WooCommerce store on Kubernetes, a custom WooCommerce MCP server, a team MCP gateway with per-user keys and audit records, two demo upstream servers, a React dashboard, and an LLM chat tool loop.

## What is included

- **Store:** WordPress + WooCommerce in the cluster. MySQL, WordPress content and gateway SQLite data use persistent volumes.
- **WooCommerce MCP:** custom Streamable HTTP server in `services/woo-mcp`. It exposes `list_products`, `create_product`, `list_orders`, `get_order`, and `update_order_status` through the WooCommerce REST API.
- **Gateway:** `backend/app/main.py` authenticates user keys, acts as an MCP client to each upstream, exposes a consolidated `/mcp`, routes tools, encrypts saved upstream credentials, checks upstream health, and records each tool call.
- **Other upstreams:** `inventory-mcp` and `metrics-mcp` are independent demo MCP servers. The metrics data is intentionally sample data; it demonstrates aggregation with a second server.
- **Dashboard and chat:** `dashboard/` shows upstream status/tools, members, keys and audit data. The chat uses an OpenAI-compatible tool-call API and executes tools as the signed-in user.
- **Deployment:** `helm/urumi/` is the only deployment definition. `values-local.yaml` and `values-prod.yaml` hold environment differences.

This repository does not include the optional multi-store provisioning bonus.

## Local setup (Kind)

For a guided walkthrough with commands explained in order, see [Step-by-step build and demo guide](docs/step-by-step.md).
For a requirement-by-requirement view of implemented code versus live evidence and submission items, see [Assignment compliance tracker](docs/assignment-compliance.md).

Install Docker Desktop, Kind, kubectl, Helm 3, and PowerShell. The image build downloads the pinned WordPress/WooCommerce base and Node/Python dependencies, so Docker needs network access.

1. Create a Kind cluster with ports mapped for ingress and the default CNI disabled:

   ```powershell
   kind create cluster --name urumi --config kind-calico.yaml
   ```

2. Install Calico before deploying workloads. This is required because Kind's default `kindnet` does not enforce the chart's NetworkPolicy. `kind-calico.yaml` sets the pod CIDR to `192.168.0.0/16`, matching the Calico custom resource defaults:

   ```powershell
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/v3_projectcalico_org.yaml
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
   kubectl wait --for=condition=Available --timeout=180s deployment/tigera-operator -n tigera-operator
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/custom-resources.yaml
   kubectl wait --for=condition=Ready nodes --all --timeout=300s
   kubectl get pods -A | findstr /i "calico tigera"
   ```

   Confirm the Calico pods are `Running` before continuing. Calico 3.33 documents support for Kubernetes 1.37. See the [official Kind installation guide](https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind).

3. Install local persistent-volume and ingress controllers:

   ```powershell
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
   kubectl wait --namespace ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
   ```

4. Create Kubernetes Secrets (the script prompts for passwords and creates a Fernet encryption key; no credentials are written into the repo):

   ```powershell
   .\scripts\create-secrets.ps1
   ```

   Local values run Ollama in Kubernetes with the small Qwen2.5 0.5B model, so chat works without an external API key or API credits. Model weights persist in the `ollama-models` PVC. Production values default to OpenAI-compatible API settings; create `OPENAI_API_KEY` in `gateway-secrets` only if using a paid provider.

5. Build and load the application images into Kind:

   ```powershell
   .\scripts\build-local.ps1
   ```

6. Install the Helm release:

   ```powershell
   helm upgrade --install urumi .\helm\urumi -n urumi --create-namespace -f .\helm\urumi\values-local.yaml
   kubectl -n urumi rollout status statefulset/mysql
   kubectl -n urumi rollout status deployment/wordpress
   kubectl -n urumi rollout status deployment/gateway
   ```

   The chart installs `woo-mcp-gateway-only`. Verify that the gateway can reach WooCommerce MCP and the inventory pod cannot:

   ```bash
   kubectl -n urumi get networkpolicy
   kubectl -n urumi exec deployment/gateway -- python -c 'import urllib.request; print(urllib.request.urlopen("http://woo-mcp:8001/healthz", timeout=5).status)'
   kubectl -n urumi exec deployment/inventory-mcp -- python -c 'import socket,sys; socket.create_connection(("woo-mcp",8001),timeout=3); print("UNEXPECTEDLY REACHABLE"); sys.exit(1)'
   ```

   The gateway request should print `200`. The inventory request should time out (an exec error from the timed-out connection is expected), demonstrating that Calico enforces the policy. The policy permits WooCommerce MCP ingress only from pods labeled `app: gateway`.

7. Add this line to the Windows hosts file (run an editor as Administrator):

   ```text
   127.0.0.1 urumi.local dashboard.urumi.local
   ```

   The Kind config maps host ports 80/443 to the ingress controller. Open `http://urumi.local` for the store and `http://dashboard.urumi.local` for the dashboard.

### Prepare the WooCommerce MCP connection

The WooCommerce server is registered in the gateway at install time. The REST key is created inside the store after its first boot:

1. Sign in at `http://urumi.local/wp-admin` with the WordPress admin email/password entered into the secret setup script.
2. Create a dedicated WordPress user with the **Shop manager** role.
3. In WooCommerce, go to **Settings → Advanced → REST API → Add key**. Select that user and **Read/Write**, then create the key.
4. Store its consumer key and consumer secret in a Kubernetes Secret and restart the adapter so it reads the new values:

   ```powershell
   kubectl -n urumi create secret generic woocommerce-api --from-literal=WC_CONSUMER_KEY='<consumer-key>' --from-literal=WC_CONSUMER_SECRET='<consumer-secret>' --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n urumi rollout restart deployment/woo-mcp
   ```

The credentials are only mounted into the WooCommerce MCP pod. That service is a ClusterIP and has no Ingress. Calico enforces the chart's NetworkPolicy, which permits inbound WooCommerce MCP traffic only from the gateway pod; install a policy-capable CNI in production as well. The adapter calls WooCommerce REST at `http://wordpress/wp-json/wc/v3`; the gateway calls the adapter over the cluster network. This keeps the WooCommerce API credential away from browsers and MCP clients. In production, use TLS between the adapter and store if they cross an untrusted network.

## Using the dashboard and required demo flow

The initial admin email is `admin@urumi.local`; its password is the one entered in `create-secrets.ps1`.

1. Sign in as the admin and create member A and member B from **Team**. Use different passwords.
2. Create an API key for member A; the dashboard shows the raw key once. Keep it private. Sign in as A and open **Chat**.
3. Ask the assistant to create a product with a specific name and price. Check the storefront product page.
4. Add that product to the cart and complete checkout using **Cash on delivery**. Check the order in WooCommerce admin.
5. Ask Chat: “What orders came in today?” WordPress and the chat use the Asia/Kolkata store timezone; the system prompt gives the exact local-day interval for the WooCommerce order query. The chat response shows the tools it used; the audit log attributes calls to A.
6. Sign in as B in a separate browser profile, create B's own API key, and connect MCP Inspector (or another Streamable HTTP MCP client) using just `http://dashboard.urumi.local/mcp` and `Authorization: Bearer <B-key>`. The gateway lists namespaced tools such as `woocommerce__list_orders` and `inventory__search_inventory_notes`.
7. Use an MCP-enabled AI client (such as Claude Code or Cursor) for natural-language prompts; MCP Inspector is useful for listing and calling tools manually, but it does not provide a chat prompt. Ask the client about today's orders. For a prompt involving two independent upstreams, ask: “Search the inventory notes for the product named Sample Item and get today's store metrics; summarize both.” This uses `inventory__search_inventory_notes` and `metrics__get_store_metrics`. The dashboard Chat can also demonstrate the same cross-upstream request while signed in as B; its tool calls are still authenticated and audited as B.
8. Revoke B's MCP key from **API keys**. B's next client request should receive HTTP 401. Disable either demo upstream from **Servers** and reload `tools/list`; its tools are omitted. Re-enable it after the demo.
9. To demonstrate upstream failure, delete the inventory pod and immediately refresh server status while Kubernetes replaces it:

   ```powershell
   kubectl -n urumi delete pod -l app=inventory-mcp
   ```

   The dashboard reports `Unreachable` during the restart window. Gateway tool discovery reports that upstream separately and continues listing/calling the other servers. The MCP endpoint is `http://dashboard.urumi.local/mcp`; on production it uses the HTTPS dashboard hostname.

## Production-like deployment (k3s)

Install k3s with its Ingress controller and local-path StorageClass, build and push the five images from `backend/`, `dashboard/`, `services/woo-mcp/`, `services/demo-mcp/`, and `store/`, then update the image repositories/tags in `values-prod.yaml`. Point DNS at the VPS and use the installed Ingress class (Traefik by default in k3s). Create a TLS Secret (or configure cert-manager), then create `gateway-secrets` and `wordpress-secrets` with the same key names used by the local setup script. Create `woocommerce-api` after setting up the store REST key. Use an external secret manager and enable Kubernetes Secret encryption at rest for a real deployment.

Install or upgrade with:

```sh
helm upgrade --install urumi ./helm/urumi -n urumi --create-namespace -f ./helm/urumi/values-prod.yaml
```

The chart stays the same. Values change the hostnames, scheme, Ingress class/TLS, image locations, StorageClass, PVC sizes and resource sizing. Set `hosts.store` and `hosts.dashboard` to DNS names you own, `hosts.scheme` to `https`, and `ingress.tls` to `true`. `values-prod.yaml` intentionally uses placeholder image paths and must be updated before deployment.

For an upgrade, push immutable image tags and run `helm upgrade`; inspect with `helm history urumi -n urumi`. To roll back use `helm rollback urumi <revision> -n urumi`. Back up the WordPress/MySQL/gateway PVCs before upgrades that migrate data.

## MCP design, isolation and security

Read [System design and tradeoffs](docs/system-design.md) and [Threat model](docs/threat-model.md). The key choices are:

- Tool names are prefixed `server__tool`, so upstream name collisions are deterministic and visible.
- Each server discovery/call has a five-second timeout. Failed upstreams are isolated and appear as status failures; other servers remain available.
- The gateway negotiates upstream MCP sessions and accepts JSON or SSE JSON-RPC responses. Its public `/mcp` endpoint is exposed through the dashboard Ingress; upstream MCP services have only internal ClusterIP Services. A NetworkPolicy restricts WooCommerce MCP ingress to the gateway pod when the cluster CNI enforces NetworkPolicies.
- API keys and dashboard sessions are random values; only SHA-256 hashes are stored. User passwords use PBKDF2. Upstream static credentials are Fernet-encrypted in the gateway's persistent SQLite database using `FERNET_KEY`; the encryption key and LLM key are Kubernetes Secrets.
- The gateway never forwards a client's key to an upstream. It adds only the upstream's stored credential. An upstream credential is shared: a member can invoke every enabled tool available to that key, so grant WooCommerce only the capabilities this team should have.
- URL registration requires HTTPS for public hosts, rejects non-global resolved IPs and redirects, and accepts the named demo MCP services or other MCP service DNS names in the `urumi` namespace (except the gateway, database and WordPress). This is a starter SSRF defense; production still needs egress policy and DNS-rebinding protections.

## Known scope limits

Single gateway replica and one WooCommerce store; no OAuth, per-tool authorization, rate limiting, multi-store provisioning or production VPS deployment is included in this local workspace. The demo metrics/inventory tools return sample values. Use a persistent StorageClass, real image registry and external secret management before production.
