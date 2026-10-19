# System design and tradeoffs

## Components and request path

```text
MCP client ──user API key──▶ Dashboard Ingress ──▶ Dashboard nginx ──▶ Gateway /mcp
Dashboard Chat ──session key───────────────────────────────▶ Gateway chat/tool loop
                                                               │
                         ┌─────────────────────────────────────┼─────────────┐
                         ▼                                     ▼             ▼
                   WooCommerce MCP                       Inventory MCP   Metrics MCP
                         │
                         ▼
                 WordPress/Woo REST ──▶ MySQL
```

Only the dashboard and storefront have Ingress objects. Gateway, WooCommerce MCP, demo MCP and MySQL are ClusterIP services. The dashboard's nginx proxies `/api` and `/mcp` to the gateway. External MCP clients and Chat therefore enter through the same gateway. A NetworkPolicy on WooCommerce MCP permits ingress only from gateway pods; it is effective only with a NetworkPolicy-enforcing CNI, which must be installed for both local and production clusters. WooCommerce MCP is the only custom component with WooCommerce API access. Its WooCommerce REST credentials are mounted from `woocommerce-api` only into that pod. For local HTTP, the adapter connects to WordPress through its internal Service but signs OAuth 1.0a requests against the canonical storefront URL configured in Helm; this matches WooCommerce's signature validation without sending the consumer secret in clear text. HTTPS endpoints use HTTP Basic authorization. WordPress, MySQL, and the gateway each receive only their relevant Secrets. Persistent claims hold WordPress files/uploads, MySQL data and gateway/audit data.

## MCP aggregation, routing and failures

For each enabled upstream the gateway negotiates MCP initialization, retains any returned `MCP-Session-Id` for that upstream URL, and discovers tools. JSON and SSE responses are handled. The gateway concatenates tools under `<server-name>__<upstream-tool-name>`; for example, `inventory__search_inventory_notes`. This namespace prevents collisions even when two upstreams publish the same tool name. The prefixed name is what clients see and send back; the gateway strips the prefix by selecting the corresponding upstream tool.

Every upstream request has a five-second timeout, does not follow redirects, and sends that server's stored static credential. Discovery catches errors per server and continues to later servers. Status is determined by live tool discovery. A call is audited even on an exception or tool-level error. The audit row includes user id/email, server and original tool name, UTC timestamp, elapsed milliseconds, success flag and error text. Admins see all rows; members see only their own.

The chat gets the same discovered tool schemas and invokes the same `do_call` function with the authenticated dashboard user. The LLM's provider key is a Kubernetes Secret; user API keys are not sent to the model or upstream. WordPress and the chat date bounds use the store timezone Asia/Kolkata; the chat system prompt gives the exact start/end timestamps for today's order query. Demo metrics/inventory tools are separate upstreams and expose sample records so the second-server flow can be demonstrated without another account.

## Local and production configuration

Both environments install `helm/urumi`. The local values point to images loaded into Kind, the `nginx` Ingress class, HTTP local domains, and local-path PVCs. Production values point to an image registry, k3s' `traefik` class, DNS names and HTTPS, a persistent StorageClass and larger claims/resources. Kubernetes Secret objects are created outside Helm and referenced by name; credentials are not templated into manifests. Production should use encrypted Kubernetes Secrets or an external secret controller and PVC backups. Helm history supports rollback; data migrations still need backup/compatibility planning.

## Tradeoffs and unimplemented scope

The gateway uses one replica and a local SQLite database on one PVC to keep the demo small. Upstream MCP session IDs are in memory, so a restart may create new sessions and horizontal scaling would need shared state or stateless upstream support. Discovery is fresh on each request, which keeps disable/removal changes immediate but costs extra upstream round trips. Local Helm values run Ollama with Qwen2.5 0.5B in-cluster and point the gateway at its OpenAI-compatible endpoint, keeping chat calls local. Production values can instead use an external OpenAI-compatible provider by changing `LLM_BASE_URL`, `LLM_MODEL` and the secret. Multi-store provisioning, OAuth, per-tool policies, rate limiting, full OpenTelemetry and TLS between in-cluster services are left as future work.
