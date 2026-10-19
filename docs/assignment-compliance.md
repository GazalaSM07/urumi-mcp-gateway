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
| Gateway aggregates/routs tools, prefixes names, isolates upstream failures, and audits calls | `backend/app/main.py` | Implemented; demonstrate collision behavior and a failed upstream live |
| Three upstreams: WooCommerce, inventory, metrics | `helm/urumi/templates/apps.yaml` | Implemented; inventory and metrics return demo data, not live business metrics |
| Team roles, individually hashed API keys, revocation, audit log | `backend/app/main.py`, dashboard | Implemented; repeat the two-user flow and capture evidence |
| Dashboard chat calls tools as the signed-in user | `backend/app/main.py`, `dashboard/src.jsx` | Implemented; cross-server chat was observed returning both tool results and audit entries |
| Design and threat model | `docs/system-design.md`, `docs/threat-model.md` | Present; explain the documented limitations in the walkthrough |

## Required live checks still to complete or capture

- [ ] Sign in as User A. Ask Chat to create a **new** product with a name and price; confirm it appears on the storefront.
- [ ] Buy that new product with Cash on Delivery; confirm the order in WooCommerce admin.
- [ ] Ask User A's Chat for today's orders; confirm it returns the new order and the audit log attributes the call to User A.
- [ ] As User B, connect an external Streamable HTTP MCP client using only the gateway URL and User B's key. Show tools from all enabled servers and retrieve today's orders.
- [ ] As User B, run one AI-client prompt that requires tools from two different upstreams. MCP Inspector can manually call tools, but it is not itself a natural-language chat client.
- [ ] Revoke User B's key and show the next client request is rejected.
- [ ] Disable one upstream and show its tools disappear from both dashboard Chat and the external client's fresh tool list; then re-enable it.
- [ ] Delete one upstream pod, show it becomes Unreachable while other upstreams still work, then wait for recovery.
- [ ] Show successful audit rows for the required calls under the correct users.
- [ ] Show namespace, Secrets (names only; never reveal values), PVCs, Ingress, probes, resource limits, and which services are internal-only.
- [ ] Demonstrate that the WooCommerce MCP NetworkPolicy is enforced by the cluster CNI. The original `urumi` Kind cluster used `kindnet`, which does not enforce Kubernetes NetworkPolicies. The separate Calico policy-test cluster previously passed the gateway-allowed / inventory-blocked connectivity check but later failed during Docker/WSL restarts; do not claim the original cluster enforces this policy without rerunning the check on an enforcing CNI.
- [ ] For a production-like deployment, replace the `YOUR_ORG` image paths and example DNS names in `values-prod.yaml`, deploy the same chart to a k3s VPS, and show the HTTPS endpoints. This deployment has not been evidenced yet.
- [ ] Publish the repository to GitHub, record the required demo video, and submit both links through the assignment form. The workspace currently has no configured Git remote and no commits, so publication/submission is still outstanding.

## Optional scope

Multi-store provisioning, OAuth, per-tool permissions, and the other listed differentiators are optional. The README documents that they are not implemented. Complete the mandatory flow and submission before attempting them.

## Walkthrough order

Use [`step-by-step.md`](step-by-step.md) for setup and demo instructions. Record the live evidence above in this order: architecture and local Kubernetes; User A store/chat flow; User B external client and cross-server prompt; key revocation and upstream controls; audit log; security/isolation; local-to-VPS configuration; upgrade/rollback story.
