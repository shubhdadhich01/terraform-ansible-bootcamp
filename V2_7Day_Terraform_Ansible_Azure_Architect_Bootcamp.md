# 7-Day Terraform + Ansible on Azure — Architect-Level Bootcamp (Production-Grade Edition)

**Audience:** Intermediate-to-advanced practitioners (DevOps engineers, cloud engineers, aspiring architects)
**Format:** One real production-pattern architecture per day → design → build with Terraform → configure with Ansible → secure → validate → tear down
**Philosophy:** Every scenario mirrors what an actual Azure landing zone / production environment looks like at a mid-market organization — hub-spoke networking, centralized firewall, private endpoints everywhere, Managed Identities, policy guardrails, and centralized logging — rather than a simplified "lab-only" version of these patterns. Complexity increases day over day the way it would in a real platform rollout. VM sizing stays on B-series/low-tier SKUs throughout; where a genuine production control (Azure Firewall, Application Gateway + WAF, Log Analytics, Private Link) adds real cost, that's called out explicitly and kept to the smallest viable SKU — a small, justified cost increase over a toy lab, in exchange for teaching the actual thing organizations run.

---

## Day 1: Enterprise Hub-Spoke Foundation with Centralized Firewall Egress

**Scenario:** "Northwind Retail" is standing up its first Azure landing zone. Rather than a flat VNet, platform engineering wants the real pattern: a hub VNet housing shared security services, and a spoke VNet for the retail web workload, with **all outbound internet traffic centrally inspected** — this is the actual starting point of nearly every enterprise Azure environment, not a simplified two-subnet demo.

**Architecture (production pattern):**
- Hub VNet containing **Azure Firewall (Basic SKU)** and a Bastion subnet
- Spoke VNet peered to hub, with `web` and `app` subnets, each with its own NSG
- **User Defined Routes (UDR)** on spoke subnets forcing all outbound traffic (0.0.0.0/0) through the Azure Firewall in the hub — the real production egress pattern, not just NSG allow/deny
- Azure Firewall network + application rule collections (allow only required FQDNs/ports outbound; deny everything else)
- Azure Bastion (Basic SKU) in the hub for admin access — no jump boxes, no public IPs on any workload VM ever

**Terraform:**
- Hub/spoke VNets, peering (both directions, `allow_gateway_transit` / `use_remote_gateways` explained even if no gateway deployed yet)
- Azure Firewall + Firewall Policy resource (rule collection groups: network rules, application rules)
- Route tables + route table associations forcing spoke egress through firewall's private IP
- 2 small Linux VMs (web + app tier, B1s), no public IPs

**Ansible:**
- Configure Nginx (web) and a sample backend app (app tier)
- Validate egress control from inside the VM (`curl` to an allowed vs. blocked FQDN, proving the firewall rule actually works — a real troubleshooting skill)
- Harden both VMs: SSH key-only, unattended-upgrades, local firewall rules mirroring NSGs

**Security focus:** Centralized network egress control (the #1 thing missing in "toy" hub-spoke labs), defense-in-depth (NSG + UDR + Firewall + no public IP), Bastion as sole admin path.

**Cost control:** Azure Firewall **Basic SKU** (not Standard/Premium) — meaningfully cheaper, sized for this exact scenario. Bastion Basic SKU. 2× B1s VMs. This is the one day with a deliberate, explained cost step-up versus a flat VNet, because centralized egress is not optional in real environments.

---

## Day 2: Private Data Plane — Storage, Key Vault & Managed Identity, Fully Locked Down

**Scenario:** "Finlytics" processes customer financial data. Production security review requires **zero public network access** to any data-plane service, and secrets must never be retrievable except by explicitly authorized identities — this is what "private by default" actually looks like end-to-end, not just one private endpoint.

**Architecture (production pattern):**
- Storage Account: public network access **disabled**, private endpoint into spoke, Private DNS Zone linked to both hub and spoke VNets (the real multi-VNet DNS pattern, not a single-VNet shortcut)
- Key Vault: public network access disabled, private endpoint, **RBAC authorization model** (not legacy access policies), purge protection enabled
- App tier VM (from Day 1, reused — production environments build incrementally, they don't rebuild from scratch daily) granted a **System-Assigned Managed Identity** with narrowly scoped roles: `Key Vault Secrets User` on one secret's scope pattern, `Storage Blob Data Reader` on one container only
- Diagnostic settings on both Storage and Key Vault streaming to a Log Analytics Workspace (introduced here, reused every day after)

**Terraform:**
- Private DNS zones (`privatelink.vaultcore.azure.net`, `privatelink.blob.core.windows.net`) with **VNet links to both hub and spoke** — the real pattern for centralized DNS resolution
- Log Analytics Workspace + diagnostic settings (30-day retention)
- Role assignments scoped as narrowly as the platform allows

**Ansible:**
- Deploy a script proving zero-credential access: fetch a secret from Key Vault and a blob from Storage using only the Managed Identity token endpoint
- Configure local audit logging of every access attempt (auditd or equivalent)

**Security focus:** Private-by-default data plane, multi-VNet private DNS resolution (a real gap most tutorials skip), least-privilege RBAC scoped to resource, not subscription, centralized diagnostic logging as a day-one habit rather than an afterthought.

**Cost control:** No new VMs — reuses Day 1's app VM. Log Analytics on pay-as-you-go with capped daily ingestion. Private endpoints and Key Vault operations are low-cost at lab scale.

---

## Day 3: Internet-Facing Production Ingress — Application Gateway + WAF + Autoscaling Backend

**Scenario:** "Bloom Events" runs flash ticket sales with unpredictable spikes and is a public target for bot traffic and common web exploits. A raw Load Balancer isn't the production answer here — **Application Gateway with WAF_v2** is the actual pattern organizations use for internet-facing HTTP(S) workloads that need both scaling and OWASP-grade protection.

**Architecture (production pattern):**
- Application Gateway (WAF_v2 SKU, smallest viable capacity/autoscale range) in a dedicated `appgw` subnet, OWASP Core Rule Set in **Prevention mode**
- Backend pool: a small Virtual Machine Scale Set (min 1, max 2 instances) in the spoke `web` subnet — no public IPs on any instance, App Gateway is the sole ingress
- Health probes, HTTP-to-HTTPS redirect, TLS certificate served from **Key Vault** (real integration: App Gateway pulling certs directly from Key Vault via Managed Identity, not uploading a .pfx manually)
- NSG on the web subnet allowing traffic **only from the Application Gateway subnet and GatewayManager tag** — the exact production rule, not a generic "allow 80/443 from internet"

**Terraform:**
- Application Gateway resource with WAF policy, backend pool, HTTP settings, listeners, routing rules
- VMSS with autoscale rule (CPU-based), custom health endpoint dependency
- User-assigned Managed Identity on App Gateway with `Key Vault Certificate User` role for cert retrieval

**Ansible:**
- Configure identical Nginx web servers across scale set instances (idempotency proof: run twice, diff output)
- Custom `/healthz` endpoint for the App Gateway probe
- Configure structured access logging shipped to the Day 2 Log Analytics Workspace

**Security focus:** WAF as the actual first line of defense for internet-facing apps (not just NSGs), certificate lifecycle via Key Vault instead of manual uploads, backend instances with zero direct exposure — App Gateway is the only path in.

**Cost control:** WAF_v2 with autoscale **min capacity set to smallest allowed**, VMSS capped at max 2× B1s instances, torn down immediately after the scaling demonstration. This is the second deliberate, explained cost step-up — WAF-grade ingress is a real production requirement for public workloads, not a nice-to-have.

---

## Day 4: Zero-Trust Administration — JIT Access, Full Audit Trail & NSG Flow Logs

**Scenario:** "Cedar Health" is a healthcare software vendor under compliance review. Auditors require proof that **no standing administrative access exists anywhere**, every access request is time-boxed, and every network flow is captured — this is the real "prove it" bar production security teams are held to, not a checkbox.

**Architecture (production pattern):**
- Microsoft Defender for Cloud **Just-In-Time (JIT) VM Access** applied to every VM built so far (Day 1–3 resources), configured as policy rather than a one-off request
- NSG Flow Logs (version 2, with traffic analytics) on every subnet, shipped to the Log Analytics Workspace from Day 2
- Azure Monitor alert rule firing on any JIT access request — the real detective control auditors ask for
- Bastion (from Day 1) reused as the sole path even during a JIT-approved window — JIT and Bastion are complementary, not redundant, and production environments run both

**Terraform:**
- JIT policy configuration via the `azapi` provider (a real-world gap: native `azurerm` support is limited, and this is a genuine skill practitioners need — working around provider gaps is architect-level work)
- NSG Flow Log resources + Traffic Analytics workspace configuration
- Azure Monitor action group + alert rule on JIT request activity

**Ansible:**
- Configure `auditd` (Linux) for command-level audit logging on every VM
- Configure log forwarding from each VM to the Log Analytics Workspace (via the Azure Monitor Agent, not the deprecated legacy agent — a real current-state distinction to teach)
- SSH hardening: key-only, fail2ban, idle timeout — reinforced across every VM in the environment, not just one

**Security focus:** JIT + Bastion + NSG Flow Logs + auditd as a layered, auditable control set — this day is explicitly about proving controls, the actual deliverable a production security review asks for.

**Cost control:** No new VMs. Traffic Analytics processing interval set to the lower-cost option (10 min, not 1 min). Log Analytics retention capped at 30 days.

---

## Day 5: Encryption & Key Management at Production Standard — CMK, Rotation & TLS End-to-End

**Scenario:** "Ledger Trust," a fintech reporting platform, is being audited against a customer contract requiring **customer-managed keys with documented rotation**, not just "encryption enabled" — the actual bar for regulated data, where "Microsoft manages the keys" isn't an acceptable answer.

**Architecture (production pattern):**
- Key Vault (from Day 2) extended with a **Customer-Managed Key (CMK)** used for Azure Disk Encryption on the app-tier VM, with purge protection and soft-delete already enforced
- A documented **key rotation policy** on the Key Vault key (Azure-native rotation policy, not manual rotation) — the real production expectation, taught as configuration, not a one-time setup
- TLS end-to-end: Application Gateway (Day 3) already terminates TLS using a Key Vault-issued certificate; this day adds **re-encryption from App Gateway to backend** (not just TLS at the edge) — the actual "TLS everywhere" pattern auditors expect for regulated workloads
- Storage Account (Day 2) also updated to use the same CMK for a unified key management story across compute and storage

**Terraform:**
- Disk Encryption Set referencing the CMK, applied to the VM's managed disk
- Key rotation policy resource on the Key Vault key (e.g., rotate every 90 days, notify 30 days before expiry)
- Backend HTTPS settings on Application Gateway with a backend certificate/trusted root — real config most tutorials skip because it's fiddly, but it's exactly what auditors check

**Ansible:**
- Verify encryption status at the OS level (disk checks)
- Configure Nginx for backend HTTPS matching the App Gateway's re-encryption expectation
- Configure a rotation-awareness check (a script that queries Key Vault for the key's next rotation date and logs a warning if it's within 7 days) — teaches operational awareness, not just one-time setup

**Security focus:** CMK vs. platform-managed keys (the actual audit distinction), automated key rotation as policy, TLS re-encryption end-to-end rather than "TLS at the edge only" — the gap that fails most real security reviews.

**Cost control:** No new VMs (reuses Day 1–3 resources). CMK and rotation policy costs are per-operation and negligible at lab scale.

---

## Day 6: Governance at Scale — Policy-as-Code, Initiatives & Automated Compliance Reporting

**Scenario:** "Solstice Manufacturing" now has multiple teams deploying into the environment built across Days 1–5, and platform engineering needs **org-wide guardrails enforced automatically**, plus a way to prove compliance to leadership — the actual "governance at scale" problem, addressed with an Azure Policy **initiative** (policy set), not a single standalone policy.

**Architecture (production pattern):**
- An Azure Policy **initiative** bundling multiple policies: deny public IPs, require mandatory tags (`environment`, `owner`, `costcenter`), restrict allowed VM SKUs and regions, require HTTPS-only on storage — assigned at the resource-group scope over the entire Days 1–5 environment (real guardrails applied retroactively, exactly as it happens when governance catches up to an existing environment)
- A deliberately non-compliant Terraform plan submitted first to demonstrate policy **deny** in real time, then corrected — the actual "shift-left governance" teaching moment
- Compliance reporting: a scheduled Ansible-driven compliance sweep across every resource built so far, producing a simple pass/fail report per policy — the real "prove it to leadership" deliverable, not just a portal screenshot

**Terraform:**
- `azurerm_policy_set_definition` (initiative) bundling 4–5 policy definitions
- `azurerm_resource_group_policy_assignment` applied over the full environment
- A toggleable "violating" resource block to demonstrate enforcement live, followed by the corrected version

**Ansible:**
- A compliance-sweep playbook using Azure CLI modules to inspect every resource built across Days 1–5 for required tags and configuration, producing a structured report (JSON/CSV) — this is the day Ansible is used explicitly as a **compliance/reporting tool**, not a configuration tool, an important architect-level distinction
- This playbook is designed to be re-run on a schedule in production (cron/Ansible Tower/AWX concept discussed, not necessarily built)

**Security focus:** Preventive controls (policy deny) vs. detective controls (compliance sweep), retroactive governance over an already-running environment (the realistic scenario, not a greenfield policy-first build), tagging as the backbone of cost and ownership accountability.

**Cost control:** Policy resources are free. No new VMs. The compliance sweep runs against existing resources only.

---

## Day 7: Event-Driven Integration at Production Scale — Serverless Processing with Full Observability

**Scenario:** "Harbor Logistics" needs uploaded shipment manifests to trigger validation and downstream processing automatically, integrated into the **same secured, governed, observed environment** built across the week — not a standalone serverless demo, but serverless landing into an already-governed landing zone, which is how it actually gets built in production.

**Architecture (production pattern):**
- Storage Account (from Day 2, same private-endpoint pattern) with a Blob container as the event source
- **Azure Function App (Consumption plan)** with a Blob-triggered function, deployed with **VNet integration** so it can reach the private Storage/Key Vault endpoints from Days 1–2 (the real production requirement — a Function that can't reach private resources is not a usable production pattern)
- Function App using System-Assigned Managed Identity, role-scoped to one container and one Key Vault secret only
- Function execution telemetry via Application Insights, wired into the same Log Analytics Workspace used since Day 2 — one observability pane across VMs, App Gateway, Firewall, and now Functions
- The Day 6 policy initiative automatically evaluates the new Function App and Storage changes for compliance — proving the governance built on Day 6 actually holds up against new workload types, not just VMs

**Terraform:**
- Function App (Consumption/Y1) with VNet integration subnet (delegated subnet in the spoke)
- Application Insights linked to the existing Log Analytics Workspace (workspace-based mode, the current production-recommended pattern)
- Role assignments scoped narrowly, consistent with every prior day

**Ansible:**
- A small control VM (B1s, reused pattern from Day 1) configured to upload test manifests and poll Application Insights/Log Analytics for execution results — proving the integration end-to-end
- This is the explicit teaching moment on where Ansible fits (config management) versus where it doesn't (PaaS compute) — an important distinction for architects choosing tools

**Security focus:** VNet-integrated serverless compute reaching private endpoints (the real production pattern, harder than the "public Function calling public Storage" tutorial version), least-privilege Managed Identity scoped to one resource, governance policies proven to apply beyond VMs.

**Cost control:** Function App Consumption plan costs cents at lab scale; VNet integration itself has no compute cost. No new persistent VM beyond the reused control VM. Application Insights capped daily quota.

---

## Cost Philosophy (applies across all 7 days)

- Default VM size: **Standard_B1s / B2s** throughout — this never changes, regardless of scenario complexity
- Three deliberate, explained cost increases over a "toy lab" — Azure Firewall Basic (Day 1), Application Gateway WAF_v2 with minimum autoscale capacity (Day 3), and Log Analytics ingestion (from Day 2 onward) — each is a genuine production control, not an inflated demo, and each is sized to the smallest SKU/capacity that still teaches the real behavior
- No Premium SKUs anywhere (Firewall Basic not Premium/Standard where avoidable, Bastion Basic not Standard, WAF_v2 at minimum autoscale range)
- The environment is built **incrementally across the week** (Days reuse prior days' VMs and resources rather than rebuilding), which mirrors real platform rollouts and also keeps total concurrent resource count low
- Every day ends with a `terraform destroy` step for that day's new resources as a mandatory lab exercise; the cumulative environment is destroyed in full at the end of Day 7
- Participants see estimated hourly cost **before** provisioning each day, using `terraform plan` output cross-checked against the Azure Pricing Calculator

## Tooling Baseline (Day 0 prerequisite, not a bootcamp day)

- Terraform CLI, Azure CLI, Ansible installed and authenticated
- Azure subscription with Contributor access (or scoped custom role) at a dedicated Resource Group
- Git repository per participant for versioning Terraform/Ansible code
- `tflint` and `checkov`/`tfsec` introduced on Day 1 as a running static-analysis practice, used through Day 7 — real teams don't `terraform apply` unscanned code, and neither does this bootcamp

---

## Capstone (Separate from the 7-Day Curriculum) — "Apex Bank" Secure Internal Portal

> Delivered as an optional standalone module, run separately from Days 1–7 (e.g., as a follow-on assessment or take-home project). It is not "Day 8" — it composes the week's patterns into one coherent, audited, production-shaped architecture and adds the two things a real environment needs that a single week can only gesture at: **modularized IaC** and **remote state with locking**.

**Scenario:** Apex Bank needs an internal employee portal that is representative of a real regulated-industry deployment: hub-spoke with centralized firewall egress, WAF-protected ingress, private data plane with CMK encryption, JIT-only administration, NSG flow logs, and policy governance — all composed, not rebuilt.

**Architecture (composition of Days 1–7, not new concepts):**
- Hub-spoke with Azure Firewall egress (Day 1)
- Private Storage/Key Vault with Managed Identity (Day 2)
- Application Gateway + WAF ingress with Key Vault-issued certs (Day 3)
- JIT access, NSG flow logs, audit logging (Day 4)
- CMK disk/storage encryption with rotation policy, TLS re-encryption end-to-end (Day 5)
- Policy initiative + automated compliance sweep (Day 6)
- VNet-integrated Function App for event-driven processing (Day 7)

**Terraform:**
- Fully modularized configuration — each day's pattern becomes a reusable module: `network`, `security`, `compute`, `keyvault`, `policy`, `serverless`
- **Remote state** on an Azure Storage backend with state locking — introduced formally here as the non-negotiable production practice it is
- `terraform plan` output reviewed as a change-management artifact, tying the week back to how real architects operate

**Ansible:**
- A master playbook orchestrating role-based configuration (`webserver`, `hardening`, `secrets-fetch`, `tls-setup`, `audit-logging`, `compliance-sweep` roles), each pulled from the week's work
- Idempotency re-verified by running the full playbook twice and diffing output

**Security focus:** The full defense-in-depth stack demonstrated end-to-end — this is explicitly a synthesis and IaC-maturity exercise, not a new scenario, and can be used standalone as a portfolio capstone or architect-level assessment.

**Cost control:** Capped at the same 3–4 small VMs used across the week (Function App and Application Gateway remain PaaS/managed, not additional VMs); full environment destroyed via `terraform destroy` with a documented teardown checklist.
