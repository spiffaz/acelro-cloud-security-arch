# Incident Response Playbook

**Platform:** ClearPay FinTech — AWS + Azure multi-environment
**Scope:** Production, Staging, Dev
**Last reviewed:** 2026-05-10

---

## Severity Levels and Response SLAs

| Severity | Label | Definition | Initial Response | Containment Target | Resolution Target |
|----------|-------|------------|-----------------|-------------------|------------------|
| P0 | Critical | Active breach, data exfiltration in progress, PCI-scoped systems compromised | 15 minutes | 1 hour | 4 hours |
| P1 | High | Unauthorized access confirmed, suspected data exposure, service unavailability | 30 minutes | 2 hours | 8 hours |
| P2 | Medium | Policy violation, suspicious activity, single failed control | 2 hours | 8 hours | 24 hours |
| P3 | Low | Anomalous but non-threatening behavior, informational alert | Next business day | 48 hours | 72 hours |

---

## Communication Matrix

| Role | Name / Contact | Notified For | Channel |
|------|---------------|-------------|---------|
| Security Lead (on-call) | PagerDuty rotation — `security-oncall` | All P0/P1 | PagerDuty |
| Engineering On-call | PagerDuty rotation — `engineering-oncall` | All P0/P1 | PagerDuty |
| CISO / Head of Security | `ciso@clearpay.io` | P0 only | Phone + Email |
| Legal & Compliance | `compliance@clearpay.io` | P0, P1 with PII/PAN exposure | Email |
| Data Protection Officer | `dpo@clearpay.io` | Any incident with EU resident PII | Email (72h GDPR clock starts) |
| Payment Network (Visa/Mastercard) | Account manager contacts | P0 involving card data | Phone |
| AWS Support | Support case — Enterprise tier | AWS-side incidents P0/P1 | AWS Console |
| Azure Support | Support case — Premier tier | Azure-side incidents P0/P1 | Azure Portal |
| PR / Communications | `comms@clearpay.io` | P0 only, after legal review | Email |

**Note:** External notification (regulators, affected users) is coordinated by Legal. Engineering does not communicate externally without Legal sign-off.

---

## Incident Type 1: Unauthorized Access

### Detection Signals

| Source | Signal |
|--------|--------|
| AWS GuardDuty | `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B`, `Recon:IAMUser/UserPermissions` |
| AWS CloudTrail | Multiple `ConsoleLogin` failures followed by success from a new IP/geo |
| AWS IAM Access Analyzer | New cross-account or external principal access to a resource |
| Azure Entra ID Sign-in Logs | MFA challenge bypassed, sign-in from atypical location |
| Azure Defender for Identity | Lateral movement alerts, pass-the-hash detection |
| SIEM / CloudWatch Alarms | `>5 failed API calls in 60s` from the same identity |

### Severity Assessment

- **P0:** Privileged role (admin, CI/CD deploy role) compromised; active API calls modifying resources
- **P1:** Non-privileged IAM user or service account compromised; read-only access to sensitive data confirmed
- **P2:** Suspicious login attempt blocked; no confirmed access

### Initial Triage

1. Identify the affected principal: IAM user, role, service account, or federated identity.
2. Pull CloudTrail / Entra audit logs for the last 24 hours filtered to that principal.
3. Determine the source IP, user-agent, and actions taken.
4. Check whether MFA was satisfied or bypassed.
5. List all resources touched: S3 buckets, RDS, Secrets Manager, Key Vault.
6. Determine whether any data was read, written, or exfiltrated (see Incident Type 2 if yes).

### Containment Actions

- [ ] Revoke all active sessions for the compromised principal (`aws iam delete-login-profile` / Entra sign-in session revoke)
- [ ] Detach or disable the IAM policy / Entra role assignment
- [ ] Rotate all credentials and API keys associated with the principal
- [ ] If EC2/pod compromise is suspected: isolate the instance (restrictive SG / network policy)
- [ ] Apply a deny-all SCP at the AWS account level if account-level compromise is confirmed
- [ ] Enable CloudTrail for additional API logging if not already at `ALL` events

### Eradication and Recovery

- [ ] Audit and remove any backdoor IAM users, roles, or access keys created during the incident
- [ ] Review and roll back any resource modifications (S3 bucket policies, KMS key policies, SGs)
- [ ] Rotate KMS keys if they were accessed by the compromised principal
- [ ] Re-enable access only after root cause is confirmed and patched
- [ ] Update WAF IP block list with attacker source IPs

### Escalation Contacts

- P0/P1: Security on-call (PagerDuty) + Engineering on-call + CISO
- P1 with PII exposure: Add DPO (GDPR 72h clock)
- P2: Security on-call only

---

## Incident Type 2: Data Exfiltration

### Detection Signals

| Source | Signal |
|--------|--------|
| VPC Flow Logs / Azure NSG Flow Logs | Sustained high-volume outbound traffic to unknown external IP |
| AWS S3 Access Logs | Bulk `GetObject` or `ListBucket` requests, especially from a new principal or IP |
| AWS Macie | Sensitive data (PII, financial) discovered in unexpected bucket or accessed by unusual principal |
| AWS GuardDuty | `Exfiltration:S3/ObjectRead.Unusual`, `Trojan:EC2/DNSDataExfiltration` |
| Azure Defender for Storage | Unusual data access pattern, access from Tor exit node |
| CloudWatch / Azure Monitor | DynamoDB `Scan` operations spiking; RDS slow query log showing mass `SELECT *` |
| DLP / CASB | Outbound traffic containing PAN or SSN patterns |

### Severity Assessment

- **P0:** PII, PAN, or financial records confirmed exfiltrated; exfiltration in progress
- **P1:** Suspected exfiltration; data access anomaly confirmed but volume/content unknown
- **P2:** Anomalous access pattern with no confirmed exfiltration

### Initial Triage

1. Identify the source: compromised user, service account, pod, or EC2 instance.
2. Determine what data was accessed: S3 path, DynamoDB table, RDS schema/table.
3. Classify the data (PII, PAN, authentication tokens) using the data classification table in `threat-model.md`.
4. Estimate volume: number of records, bytes transferred.
5. Identify the destination IP(s) and check against threat intel (VirusTotal, AWS GuardDuty findings).
6. Confirm whether exfiltration is ongoing or completed.

### Containment Actions

- [ ] Block destination IP(s) at AWS WAF / Azure Firewall immediately
- [ ] Revoke credentials of the source principal (same steps as Incident Type 1)
- [ ] If a pod is compromised: delete the pod, scale deployment to zero, cordon the node
- [ ] Apply S3 bucket policy to deny all `GetObject` until investigation is complete
- [ ] Enable S3 Object Lock on affected bucket (prevent delete/overwrite of evidence)
- [ ] Snapshot RDS and DynamoDB (preserve state for forensics before any rollback)
- [ ] Rotate KMS keys used to encrypt accessed data

### Notification Requirements

| Regulation | Trigger | Deadline | Owner |
|------------|---------|----------|-------|
| GDPR Art. 33 | EU resident PII confirmed in exfiltrated data | 72 hours to supervisory authority | DPO |
| GDPR Art. 34 | High risk to EU residents | Without undue delay to affected individuals | DPO + Legal |
| PCI-DSS 12.10 | Card data (PAN, CVV) confirmed | Immediate to acquiring bank + card brands | CISO + Legal |
| FCA | Material operational incident | ASAP, no later than end of business day | CISO + Legal |

### Eradication and Recovery

- [ ] Confirm exfiltration path is closed (no additional egress observed for 2 hours)
- [ ] Patch or remove the vulnerability that enabled the exfiltration
- [ ] Re-encrypt affected data stores with rotated KMS/Key Vault keys
- [ ] Notify affected users per Legal guidance
- [ ] Conduct post-incident review within 5 business days

### Escalation Contacts

- P0: All parties in communication matrix simultaneously
- P1: Security on-call + Engineering on-call + Legal (data scope may trigger notifications)

---

## Incident Type 3: WAF Rule Bypass

### Detection Signals

| Source | Signal |
|--------|--------|
| AWS WAF Logs | Requests matching known attack patterns allowed through; rule evaluation showing `ALLOW` on a request that should match a block rule |
| CloudWatch WAF Metrics | `BlockedRequests` drops to zero during an attack window |
| Application Logs | SQLi, XSS, or SSRF payloads appearing in application input |
| AWS GuardDuty | `Backdoor:EC2/C&CActivity` following a web request anomaly |
| Azure WAF / Front Door Logs | `Action: Allow` on a request with known malicious User-Agent or payload signature |
| SIEM Correlation | Spike in 400/500 errors correlated with WAF allow events |

### Severity Assessment

- **P0:** WAF bypass confirmed and actively exploited; application data modified or exfiltrated
- **P1:** WAF bypass confirmed; no evidence of exploitation yet
- **P2:** Suspected bypass; attack traffic observed but blocked by secondary control (app-layer validation)

### Initial Triage

1. Identify the specific WAF rule that was bypassed (rule ID, managed rule group name).
2. Pull the raw WAF log entry: full request URI, headers, body, source IP, matched rule.
3. Reproduce the bypass in a non-production environment to confirm.
4. Determine whether the bypass is: (a) a rule misconfiguration, (b) a missing rule, or (c) an encoding/evasion technique.
5. Check whether the bypassed request reached the application and what the response was.
6. If exploitation confirmed, pivot to Incident Type 1 or 2 as appropriate.

### Containment Actions

- [ ] Immediately add a custom WAF rule to block the specific payload pattern or source IP
- [ ] Switch the bypassed managed rule group from `COUNT` to `BLOCK` mode if it was in override
- [ ] If a specific CVE is being exploited: add a virtual patch (WAF rule) while the application fix is developed
- [ ] Enable WAF full logging (`ALL` sampled requests) for the affected distribution
- [ ] If source IPs are identifiable: add them to the IP block set in Terraform and redeploy

### Eradication and Recovery

- [ ] Root cause the bypass: encoding evasion, rule gap, or misconfigured override
- [ ] Update the WAF rule set via Terraform (not console — keep IaC as source of truth)
- [ ] Test the fix in staging with the bypass payload before deploying to production
- [ ] Review all other managed rule groups for similar overrides that could be exploited
- [ ] Submit the bypass technique to AWS/Azure if it defeats a managed rule — managed rule sets may need updating

### Escalation Contacts

- P0/P1: Security on-call + Engineering on-call
- P1 onward: review with application team lead (WAF rules may interact with legitimate traffic)

---

## Incident Type 4: Container / Kubernetes Compromise

### Detection Signals

| Source | Signal |
|--------|--------|
| AWS GuardDuty EKS Runtime Monitoring | Privilege escalation, unexpected process execution in pod |
| Falco | Runtime anomaly: shell spawned in container, unexpected outbound connection |
| Kubernetes Audit Logs | `exec` into a pod from an unexpected user; creation of privileged pod |
| Network Policy Violations | Traffic blocked by Calico/native policy logged as anomaly |
| Image Scan (Trivy in CI) | Critical CVE in deployed image that was merged despite scan failure |

### Severity Assessment

- **P0:** Cluster admin access obtained; lateral movement to cloud credentials (IMDS)
- **P1:** Container escape attempted or succeeded; access to secrets mount confirmed
- **P2:** Anomalous process in container; no evidence of escape or data access

### Containment Actions

- [ ] Cordon and drain the affected node (`kubectl cordon <node>`)
- [ ] Delete the compromised pod
- [ ] Apply a restrictive NetworkPolicy to isolate the namespace
- [ ] Revoke the pod's ServiceAccount token (rotate IRSA role if AWS)
- [ ] Block the compromised image digest in the container registry policy
- [ ] If IMDS was accessed: rotate all IAM credentials associated with the node role

---

## General Response Checklist (all incident types)

- [ ] Create an incident ticket with timestamp, severity, and initial description
- [ ] Page on-call per severity level
- [ ] Open a dedicated incident channel (#incident-YYYY-MM-DD-slug)
- [ ] Preserve evidence before making changes (snapshots, log exports, pcap if available)
- [ ] Document every action taken with timestamp and operator
- [ ] Do not delete or modify logs — S3 Object Lock and CloudTrail log validation protect integrity
- [ ] Conduct a post-incident review (PIR) within 5 business days for P0/P1
- [ ] File a PIR document in `docs/pir/YYYY-MM-DD-incident-slug.md`
