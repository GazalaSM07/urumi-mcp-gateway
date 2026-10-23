# Assignment compliance tracker

This tracker separates code that is present from behaviors that must be shown live. A chart template or README instruction is not proof that a deployment or demo step succeeded.

## Implemented in the repository

| Assignment requirement | Implementation/evidence location | Status |
|---|---|---|
| WordPress/WooCommerce, MySQL, gateway, dashboard, and three upstream MCP services run as Kubernetes workloads | `helm/urumi/templates/` | Implemented; verify fresh rollout before recording |
| One chart supports local and production-like values | `helm/urumi/values-local.yaml`, `helm/urumi/values-prod.yaml` | Implemented; production image/host placeholders still need real values |
| Persistent MySQL, WordPress, gateway, and local Ollama storage | `helm/urumi/templates/storage.yaml`, `mysql.yaml`, `wordpress.yaml`, `ollama.yaml` | Implemented; verify claims are Bound in the demo cluster |
| Ingress, probes, and resource requests/limits | `helm/urumi/templates/` | Implemented; inspect live resources during the video |
| Custom WooCommerce Streamable HTTP MCP tools | `services/woo-mcp/main.py` | Implemented; verify all five tools against the running store |
| Gateway aggregates/routs tools, prefixes names, isolates upstream failures, and audits calls | `backend/app/main.py` | Implemented; discovery/status checks run concurrently so an unavailable upstream does not hold up the others; demonstrate a failed upstream live |
| Three upstreams: WooCommerce, inventory, metrics | `helm/urumi/templates/apps.yaml` | Implemented; inventory and metrics return demo data, not live business metrics |
| Team roles, individually hashed API keys, revocation, audit log | `backend/app/main.py`, dashboard | Implemented; repeat the two-user flow and capture evidence |
| Dashboard chat calls tools as the signed-in user | `backend/app/main.py`, `dashboard/src.jsx` | Implemented; cross-server chat was observed returning both tool results and audit entries |
| Design and threat model | `docs/system-design.md`, `docs/threat-model.md` | Present; explain the documented limitations in the walkthrough |

## Mandatory definition-of-done checks

- [x] Sign in as User A. Create a product, buy it with Cash on Delivery, and confirm the order in WooCommerce admin.
- [x] Ask User A's Chat for today's orders; the new order was returned and the audit log attributed the call to User A.
- [x] As User B, connect an external Streamable HTTP MCP client using the gateway URL and User B's key; show gateway tools and retrieve today's orders.
- [x] As User B, use Cursor for a prompt requiring inventory and metrics tools from two upstreams.
- [x] Revoke User B's key and confirm the next client request is rejected; issue a replacement key and reconnect.
- [x] Disable inventory and confirm its tools disappear from Cursor; Dashboard Chat returned metrics without calling inventory. Re-enable inventory afterward.
- [x] Scale the inventory deployment to zero, confirm its gateway status becomes Unreachable while WooCommerce and metrics remain Connected, then restore one replica.
- [x] Confirm successful audit rows for the demo calls under the expected users.
- [x] Verify live PVC status, Ingress routing, probes, resource limits, and internal-only Services. The local cluster reported all expected PVCs Bound, both Ingresses present, probes and resource settings on workloads, and ClusterIP Services. Capture these checks in the final demo video.
- [x] Verify that a Calico CNI enforces Kubernetes NetworkPolicies. In isolated cluster `kind-urumi-policy-check`, all Calico pods reached `Running`; in namespace `calico-policy-test`, the client reached NGINX before a policy, timed out after `deny-web`, and reached NGINX again after `allow-client`. After restarting the cluster, a fresh `client-retest` pod also reached NGINX through the allow policy. The policy-check container was stopped afterward to reduce RAM use; it was not deleted. This proves Calico enforcement in the isolated test namespace.
- [x] Verify Calico enforcement for the three chart-defined gateway-only MCP policy rules. In the isolated `calico-policy-test` namespace, `scripts/verify-calico-upstream-policies.ps1` applied rules matching the chart selectors and pod ports. All six live checks passed: gateway access succeeded for WooCommerce (8001), inventory (8002), and metrics (8002), while a non-gateway peer was blocked from all three. This verifies policy enforcement and the chart rule semantics; the rules were exercised in a dedicated test namespace rather than by deploying the full Helm release on Calico. The main `urumi` cluster uses `kindnet`, so its NetworkPolicy objects alone are not proof of enforcement.
- [x] Provide production-like values and document how to configure the same Helm chart for k3s. `values-prod.yaml` selects Traefik, HTTPS, DNS host fields, persistent storage sizes, and production resource limits; `README.md` and `docs/step-by-step.md` document image publishing, DNS/TLS, secrets, storage, install, upgrade, and rollback steps. The NGINX timeout annotations are conditional on the NGINX class, and the gateway admin email is configurable.
- [ ] Publish the repository to GitHub, record the required demo video, and submit both links through the assignment form. A local commit exists, but no Git remote is configured and nothing has been published or submitted. The assignment form is `https://forms.gle/nftwgyNeenSDmiRb6`.

## Stand-out items (optional for the core submission)

- A live VPS/k3s deployment is listed under “Other ways to stand out.” It is valuable, but the mandatory baseline is that the same Helm chart can be configured for a production-like VPS; actual VPS deployment is not required to claim the core definition of done.
- Real production image paths, DNS names, TLS certificate, production secrets, and a rendered/deployed release require a registry and domain the user does not currently have. `values-prod.yaml` is an illustrative template and has not been rendered or deployed.
- Rate limiting, multi-store provisioning, OAuth, and other listed differentiators are optional. Multi-store provisioning is explicitly a bonus.

## Optional scope

The README documents which optional features are not implemented. Finish the mandatory flow and submission before attempting them.

## Walkthrough order

Use [`step-by-step.md`](step-by-step.md) for setup and demo instructions. Record the live evidence above in this order: architecture and local Kubernetes; User A store/chat flow; User B external client and cross-server prompt; key revocation and upstream controls; audit log; security/isolation; local-to-VPS configuration; upgrade/rollback story.
