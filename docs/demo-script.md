# Assignment demo recording script

Use this as a recording checklist after the local cluster is stable. Keep the recording focused on the required behaviors; do not show passwords, raw API keys, Kubernetes Secret values, or private account details.

## Before recording

- Confirm the dashboard loads and all three upstreams report Connected.
- Confirm WooCommerce has the dedicated Shop Manager REST key configured.
- Have two member accounts ready. Keep User B's raw API key available privately for the external client setup, but never show it on screen.
- Prepare one new product name that is not already in the catalog.
- Close unrelated apps to leave enough memory for Docker Desktop and WSL.
- The main Kind cluster uses `kindnet`, so a NetworkPolicy object there is not proof of enforcement. The isolated Calico test has shown baseline traffic succeed, default-deny traffic fail, and explicitly allowed traffic succeed. `scripts/verify-calico-upstream-policies.ps1` also passed all six checks for the chart-defined upstream selectors and ports: the gateway reached WooCommerce, inventory, and metrics, while a peer pod was blocked from all three. The policy rules were exercised in a dedicated test namespace rather than by deploying the full Helm release on Calico.

## Recording sequence

### 1. Architecture and deployment (about 1 minute)

Show the repository architecture or dashboard, then the Kubernetes deployment overview. Explain that WordPress/WooCommerce is the store, the WooCommerce MCP adapter exposes store actions, the gateway authenticates users and routes tool calls, and inventory/metrics are two independent sample upstreams.

Show the internal ClusterIP Services, the two Ingress hosts, and the bound persistent volume claims. Mention that the local cluster is for the demo and that the Helm chart has separate local and production-like values.

### 2. User A: create product and order (about 2 minutes)

Sign in as User A. In Chat, request a uniquely named product with a clear INR price. Show the successful WooCommerce tool call and the new product on the storefront. Complete checkout using Cash on Delivery, then show the order in WooCommerce admin. Return to Chat and ask for today's orders; show the matching order and the audit entry attributed to User A.

### 3. User B: external MCP client and multiple upstreams (about 2 minutes)

In a separate client/profile, connect to `http://dashboard.urumi.local/mcp` with User B's own API key. Do not expose the key in the recording. Show the namespaced tool list. Ask an MCP-enabled client to search inventory notes and retrieve today's metrics, then show that both upstream tools were used. Explain that inventory/metrics are sample demo data.

### 4. Access controls and upstream resilience (about 2 minutes)

Revoke User B's key in the dashboard and show the client's next request is rejected. Issue a replacement key if needed. Disable the inventory upstream, refresh the tool list, and show inventory tools disappear while the other upstreams remain available. Re-enable inventory.

For the upstream failure demo, scale inventory to zero only if the main dashboard and enough memory are available. Show inventory becoming Unreachable while WooCommerce and metrics remain Connected. Restore inventory to one replica and wait until it reports Connected again. Do not delete pods or clusters for this demo.

### 5. Security and production configuration (about 1 minute)

Show the audit log and identify the user/tool/result fields. Explain that API keys are stored as hashes and upstream credentials stay server-side. The isolated Calico test proved enforcement for the chart-defined gateway-only policy rules: gateway traffic succeeded and peer traffic was blocked for all three upstreams. Clarify that the rules were tested in a dedicated namespace; the full Helm release was not deployed on Calico, and the local `kindnet` cluster does not prove policy enforcement.

Show `values-prod.yaml` with example image registry and host values. Explain that these must be replaced with real registry images, DNS names, TLS certificate, and production secrets before deployment. A live VPS rollout is an optional stand-out item, not required for the baseline.

## End card / submission checklist

- Repository link is public and opens without sign-in.
- Demo video link is viewable by the reviewers.
- Assignment form has both links and any requested project details.
- Do not claim upstream-specific NetworkPolicy isolation or VPS deployment unless those have actually been demonstrated.
