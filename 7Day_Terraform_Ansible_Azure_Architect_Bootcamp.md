# 7-Day Terraform + Ansible on Azure — Architect-Level Bootcamp

**Audience:** Intermediate-to-advanced practitioners (DevOps engineers, cloud engineers, aspiring architects)
**Format:** One real architecture scenario per day → design → build with Terraform → configure with Ansible → secure → validate → tear down
**Philosophy:** Every day uses B-series burstable VMs, minimal SKUs, and auto-destroy at end of session. No day requires more than 2–4 small compute instances running simultaneously. No migration scenarios — every day is a greenfield architecture build.

---

## Day 1: Secure Two-Tier Web Application (Hub-Spoke Foundation)

**Scenario:** "Northwind Retail" needs a public-facing web tier and a private application tier that can only be reached from the web tier — the canonical foundation pattern almost every later architecture builds on.

**Architecture:**
- Hub VNet (shared services concept) peered to a Spoke VNet
- Spoke VNet with `web` subnet (public-facing via NSG) and `app` subnet (private, no public IP)
- NSGs with explicit deny-by-default, allow only required ports (80/443 inbound to web, app-tier port only from web subnet)
- Azure Bastion (or a jump-box pattern) for admin access — no direct SSH from internet

**Terraform:**
- Resource groups, VNets, subnets, NSGs, NSG associations, VNet peering
- Two Linux VMs (B1s/B2s) — one web, one app tier
- Output values feeding into Ansible inventory (dynamic inventory from Terraform state)

**Ansible:**
- Configure Nginx as reverse proxy on web tier
- Configure a lightweight app (Node.js/Python Flask sample) on app tier
- Harden both VMs: disable password auth, UFW/firewalld rules mirroring NSGs, unattended-upgrades

**Security focus:** Network segmentation, least-privilege NSG rules, no public IP on app tier, SSH key-only access.

**Cost control:** 2× B1s VMs, no Bastion Standard SKU (use Basic or SSH tunnel alternative), destroy after lab.

---

## Day 2: Private Storage & Key Vault-Backed Secrets Architecture

**Scenario:** "Finlytics," a data-sensitive SaaS startup, needs application servers to read secrets and files without ever hardcoding credentials or exposing storage publicly.

**Architecture:**
- Storage Account with public network access disabled, Private Endpoint into the spoke VNet
- Azure Key Vault with Private Endpoint, RBAC-based access policies (not legacy access policies)
- VM with System-Assigned Managed Identity — no keys, no secrets in code
- Private DNS Zones for both Storage and Key Vault private endpoints

**Terraform:**
- Key Vault, storage account, private endpoints, private DNS zone + VNet links
- Managed Identity on VM + role assignments (`Key Vault Secrets User`, `Storage Blob Data Reader`)

**Ansible:**
- Deploy a small script/app on the VM that fetches a secret from Key Vault and a file from Blob Storage using Managed Identity (via Azure CLI or SDK) — proves zero-credential access
- Configure logging of access attempts locally

**Security focus:** Managed Identity over service principals, private endpoints over service endpoints, RBAC least privilege, no secrets ever touch disk or git.

**Cost control:** 1 VM, Key Vault (pay-per-operation, negligible), Standard storage — all inside free-tier-adjacent usage.

---

## Day 3: Multi-Tier App with Load Balancing & Autoscaling Awareness

**Scenario:** "Bloom Events," a ticketing platform, expects unpredictable traffic spikes during flash sales and needs a resilient, load-balanced web tier.

**Architecture:**
- Azure Load Balancer (Standard, internal or public depending on lab budget) in front of 2 web VMs in a Virtual Machine Scale Set (VMSS) — or 2 discrete VMs to keep cost down, with VMSS concepts taught conceptually
- Health probes, backend pool, load balancing rules
- NSG allowing only LB-originated traffic to backend

**Terraform:**
- Load Balancer, backend pool, health probe, LB rule
- VMSS (low instance count: min 1, max 2) or 2 VMs, whichever keeps cost minimal — instructor's call documented in cost philosophy
- Autoscale settings (CPU-based) demonstrated even if not triggered live

**Ansible:**
- Configure identical Nginx web servers across instances (idempotent playbook proving consistency across nodes)
- Custom health-check endpoint (`/healthz`) for the LB probe
- Log rotation and basic monitoring agent install

**Security focus:** No direct public IP on backend instances, LB as sole ingress, NSG restricting to LB probe IP ranges.

**Cost control:** Scale set capped at max 2 instances, Basic Load Balancer where feature parity allows, destroy immediately after demonstrating scale behavior.

---

## Day 4: Zero-Trust Bastion-less Access & Just-In-Time (JIT) Administration

**Scenario:** "Cedar Health," a compliance-conscious healthcare software vendor, must prove no standing SSH/RDP access exists into any server — all admin access is time-boxed and audited.

**Architecture:**
- Two VMs (Linux + Windows, or both Linux to reduce cost) with **no NSG rule permanently open** for SSH/RDP
- Microsoft Defender for Cloud JIT VM Access configured via Terraform (ARM/AzAPI provider or `azurerm` where supported)
- Azure Monitor + Activity Log alerting on JIT access requests
- Diagnostic settings streaming NSG flow logs to a Log Analytics Workspace

**Terraform:**
- Log Analytics Workspace, diagnostic settings, NSG flow logs (via NSG + Network Watcher)
- JIT policy definition (via `azapi` provider since native `azurerm` support is limited) — taught as a real-world gap practitioners hit
- Conditional NSG rules that stay closed by default

**Ansible:**
- Configure auditd (Linux) for command-level audit logging
- Ship logs to a local syslog aggregator or Log Analytics agent
- Harden SSH config: key-only, fail2ban, idle timeout

**Security focus:** Just-in-time access, full audit trail, defense-in-depth (NSG + JIT + auditd), Log Analytics as the single pane of glass.

**Cost control:** Log Analytics Workspace on pay-as-you-go with short retention (30 days min), 2 small VMs.

---

## Day 5: Encrypted Data Platform with Disk & Transit Encryption

**Scenario:** "Ledger Trust," a fintech reporting tool, must guarantee data is encrypted at rest (customer-managed keys) and in transit, with proof-of-configuration for an audit.

**Architecture:**
- VM with Azure Disk Encryption using a **customer-managed key (CMK)** stored in Key Vault (not platform-managed keys)
- Key Vault configured with purge protection + soft delete (non-negotiable for CMK scenarios)
- TLS termination on Nginx using a self-signed or Key Vault-issued certificate (Key Vault Certificates feature)
- Private endpoint for Key Vault reused from Day 2 pattern (reinforced, not copy-pasted)

**Terraform:**
- Key Vault with purge protection, disk encryption set, CMK-encrypted managed disk
- Certificate resource in Key Vault, referenced by VM extension or Ansible for TLS setup

**Ansible:**
- Retrieve certificate from Key Vault and configure Nginx for HTTPS-only (redirect HTTP→HTTPS)
- Verify encryption status via OS-level disk checks
- Configure automatic certificate renewal reminder (cron-based check, since full auto-rotation is out of scope for a lab)

**Security focus:** Customer-managed keys vs platform-managed, encryption in transit, purge protection to prevent key deletion attacks, TLS best practices (cipher suites, HSTS).

**Cost control:** 1 VM, single small managed disk, Key Vault costs negligible.

---

## Day 6: Governance, Policy-as-Code & Guardrails

**Scenario:** "Solstice Manufacturing" has multiple teams deploying infrastructure and needs organization-wide guardrails: mandatory tagging, allowed regions, allowed SKUs, and no public IPs without exception approval.

**Architecture:**
- Azure Policy definitions and initiative (policy set) applied at Resource Group scope
- Policies: deny public IP creation, require specific tags (`environment`, `owner`, `costcenter`), allowed VM SKU list, allowed locations
- A deliberately non-compliant Terraform plan submitted first to show policy **deny** in action, then corrected

**Terraform:**
- `azurerm_policy_definition`, `azurerm_policy_set_definition`, `azurerm_resource_group_policy_assignment`
- A sample "violating" resource block (commented/toggle) to demonstrate policy enforcement live
- Corrected resource block that passes policy

**Ansible:**
- Not used for policy itself (control-plane, not config-plane) — instead, Ansible is used to **validate compliance post-deployment**: a playbook that inspects tags and reports drift/non-compliance across VMs via Azure CLI modules
- This reinforces the architect-level distinction between infrastructure provisioning, configuration management, and governance

**Security focus:** Preventive controls (deny policies) vs detective controls (compliance scans), tagging for accountability, SKU/region restriction to prevent shadow IT cost sprawl.

**Cost control:** Policy resources are free; only 1 small VM needed to demonstrate compliant vs non-compliant deployment.

---

## Day 7: Event-Driven Automation with Managed Functions & Least-Privilege Service Identity

**Scenario:** "Harbor Logistics" wants file uploads to a storage container to automatically trigger a lightweight processing job (e.g., validation/notification), without any always-on VM handling that workload — a serverless, event-driven architecture, giving the cohort a genuinely different infrastructure shape from Days 1–6.

**Architecture:**
- Storage Account (private, Day 2 pattern reused for the endpoint but the workload itself is new) with a Blob Storage container as the event source
- Azure Function App (Consumption plan — true pay-per-execution, near-zero idle cost) with a Blob-triggered function
- Function App using a **System-Assigned Managed Identity** to read/write Storage and fetch a config value from Key Vault — no connection strings in app settings
- Event Grid (or native Blob trigger, taught both ways conceptually) routing the storage event
- A single small "control" VM used only to upload test files and observe logs — kept minimal, not part of the core serverless architecture

**Terraform:**
- Function App (Consumption/Y1 SKU), Storage Account, Application Insights for observability
- Role assignments scoping the Function's Managed Identity to only the specific storage container and specific Key Vault secret it needs (no subscription-wide roles)
- Diagnostic settings sending Function execution logs to the Day 4 Log Analytics Workspace pattern (reinforced, not rebuilt)

**Ansible:**
- Ansible's role shifts deliberately here: instead of configuring the Function App itself (PaaS, not a server), Ansible configures the **control VM** — installing Azure CLI/SDK tooling, deploying a small script that uploads test files and polls Application Insights for execution results
- Used as a teaching moment on where Ansible fits (and doesn't fit) in a PaaS-heavy architecture — an important architect-level distinction

**Security focus:** Least-privilege Managed Identity scoped to a single resource (not just "no keys" but "narrowest possible role"), Consumption-plan attack surface reduction (no OS to patch), secrets never in Function App settings as plaintext, monitoring/observability as a security control (detecting anomalous trigger volume).

**Cost control:** Function App Consumption plan costs cents for lab-scale execution; only 1 small control VM; Application Insights on a capped daily quota to avoid ingestion surprises.

---

---

## Capstone (Separate from the 7-Day Curriculum) — "Apex Bank" Secure Internal Portal

> This capstone is delivered as an optional standalone module, run separately from Days 1–7 (e.g., as a follow-on assessment day or take-home project). It is not "Day 8" — it's a distinct deliverable that composes patterns from the week into one coherent, audited architecture.

**Scenario:** Apex Bank needs an internal employee portal: a web tier reachable only through a private path, an app tier with Managed Identity access to Key Vault-stored secrets, encrypted disks, JIT admin access, NSG flow logs to Log Analytics, and policy guardrails.

**Architecture (composition of prior patterns):**
- Hub-spoke network (Day 1) with NSGs
- Private endpoints for Key Vault + Storage (Day 2)
- Load-balanced web tier (Day 3, scaled down to 2 instances)
- JIT access + Log Analytics + NSG flow logs (Day 4)
- CMK disk encryption + TLS via Key Vault certificate (Day 5)
- Policy assignment enforcing tags and blocking public IPs (Day 6)

**Terraform:**
- Modularized configuration — each prior pattern becomes a reusable module: `network`, `security`, `compute`, `keyvault`, `policy`
- Remote state (Azure Storage backend with state locking) introduced formally here as an architect-level practice
- `terraform plan` reviewed as a "change management" artifact — tie-in to real architect workflows

**Ansible:**
- Master playbook orchestrating role-based configuration: `webserver`, `hardening`, `secrets-fetch`, `tls-setup`, `audit-logging` roles pulled from earlier modules
- Idempotency re-verified by running the full playbook twice and diffing output

**Security focus:** Full defense-in-depth stack demonstrated end-to-end — a synthesis exercise, not a new scenario, structured so it can stand alone as an assessment or portfolio capstone.

**Cost control:** Capped at 3–4 small VMs max, all resources destroyed at end via `terraform destroy` with a documented teardown checklist.

---

## Cost Philosophy (applies across all 7 days)

- Default VM size: **Standard_B1s / B2s** unless a scenario specifically requires more (never exceeds B2s in this bootcamp)
- No Premium SKUs (Load Balancer Standard used only where a feature genuinely requires it, e.g., outbound rules)
- Every day ends with a `terraform destroy` step as a mandatory lab exercise, not an afterthought
- Log Analytics retention kept at minimum (30 days) to avoid ingestion/retention cost surprises
- Participants are shown estimated hourly cost per architecture **before** provisioning, using `terraform plan` output + Azure Pricing Calculator cross-check

## Tooling Baseline (Day 0 prerequisite, not a bootcamp day)

- Terraform CLI, Azure CLI, Ansible installed and authenticated
- Azure subscription with Contributor access (or scoped custom role) at a dedicated Resource Group
- Git repository per participant for versioning Terraform/Ansible code
- Recommended: `tflint`, `checkov` or `tfsec` for static security scanning of Terraform code, introduced lightly on Day 1 and used as a running practice through Day 7
