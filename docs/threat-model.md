# Threat model

## Shared upstream credentials

The gateway keeps a credential for each upstream, shared across team members. A member can invoke every enabled tool permitted by that upstream credential; hiding the credential does not reduce those capabilities. Use a dedicated least-privilege WooCommerce Shop Manager account, scope REST keys to only the required store, disable upstreams that are not needed, and treat write tools as consequential. Per-user/per-tool authorization is not implemented yet.

Upstream static credentials are encrypted in the gateway SQLite database with Fernet. `FERNET_KEY` is held in a Kubernetes Secret and only mounted into the gateway. This protects a copied database without the key, but anyone with gateway process access or Kubernetes permission to read that Secret can use/decrypt credentials. Kubernetes Secret values are base64 encoded unless the cluster enables encryption at rest; use external secrets and encryption-at-rest in production.

## User keys and isolation

Gateway API keys are generated from a cryptographically random source; only their SHA-256 digests are stored. A key can be revoked independently. The gateway validates the key on every request and attributes the tool call to the key owner. A member can manage their own keys and read their own audit rows, but cannot manage servers, users or another user's keys. An admin can manage all users, keys and upstream configurations and can view team audit events.

The end-user key is never forwarded to an upstream and does not authenticate to WooCommerce. Each upstream receives only its own configured credential. Thus a compromised upstream cannot reuse the user's gateway key, but it can use its own credential to access the store capabilities granted to it.

## Untrusted upstreams and prompt injection

An upstream controls its tool names, descriptions, schemas and results. Malicious descriptions or returned content could try to influence an LLM. The chat prompt labels tool descriptions as untrusted and tells the model to ignore embedded instructions; this is only a mitigation, not a proof. Admins should register only reviewed servers, expose the minimum tools, and inspect tool results. The gateway never executes instructions embedded in returned text by itself.

Admin-added public hosts must use HTTPS and resolve only to globally routable IPs; redirects are disabled. A small allowlist permits the demo's in-cluster services and service DNS. DNS rebinding, compromised DNS, and malicious allowed services remain risks; production should enforce egress NetworkPolicies/firewall rules and use a reviewed upstream registry. Keep upstream credentials scoped and rotate them after a suspected compromise.

## Store and team boundaries

This is a single-store team gateway, so there is no tenant boundary between different stores. One member can call any enabled tool using the shared upstream access, including write tools; approval workflows and per-tool role rules are not implemented. Members cannot list other members' raw keys because raw keys are returned once at creation and only hashes persist. Admins are trusted to manage the team's upstreams and users.
