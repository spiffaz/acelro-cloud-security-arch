# Application & Threat Model

## Application Overview

**Name:** ClearPay — Multi-Environment FinTech Platform
**Purpose:** Payment processing, account management, and KYC/AML compliance for retail and B2B customers
**Environments:** dev, staging, prod
**Cloud:** AWS (primary) + Azure (secondary/DR)

---

## Architecture Components

| Component | Technology | Hosting |
|-----------|-----------|---------|
| Frontend | React SPA | AWS CloudFront + S3 / Azure CDN |
| API Gateway | AWS API Gateway + Azure API Management | Multi-cloud edge |
| Auth Service | Node.js, OIDC/SAML, AWS Cognito | EKS / AKS |
| Payment Service | Python microservice | EKS / AKS |
| KYC/AML Service | Python, third-party SDK integration | EKS / AKS |
| Notification Service | Python, SES/SendGrid | EKS |
| Primary Database | PostgreSQL (RDS Aurora) | AWS us-east-1 |
| Cache | Redis (ElastiCache) | AWS us-east-1 |
| Document Store | DynamoDB | AWS us-east-1 |
| DR Database | Azure SQL | Azure East US |
| Message Queue | AWS SQS / Azure Service Bus | Multi-cloud |
| Secrets | AWS Secrets Manager + Azure Key Vault | Multi-cloud |
| Observability | CloudWatch, GuardDuty, Azure Sentinel | Multi-cloud |

**Third-party Integrations:**
- Stripe / Adyen — payment processing
- Jumio — KYC identity verification
- ComplyAdvantage — AML screening
- Plaid — bank account linking
- Twilio — OTP/SMS

---

## Data Classification

| Data Type | Sensitivity | Storage | Encryption Required |
|-----------|-------------|---------|---------------------|
| User PII (name, DOB, address) | High | RDS PostgreSQL | At-rest (KMS) + in-transit (TLS 1.2+) |
| Financial account data | Critical | RDS PostgreSQL + DynamoDB | At-rest (KMS) + in-transit (TLS 1.2+) |
| Payment card data (PAN, CVV) | Critical | Tokenized via Stripe Vault | Never stored in plaintext |
| Auth tokens / session data | High | Redis (ElastiCache) | In-transit (TLS) + encrypted at rest |
| KYC documents (passports, IDs) | Critical | S3 (private, SSE-KMS) | At-rest (KMS) + in-transit (TLS 1.2+) |
| Transaction history | High | RDS + DynamoDB | At-rest (KMS) + in-transit |
| Audit logs | Medium | S3 + CloudWatch Logs | At-rest (KMS), immutable (S3 Object Lock) |
| API keys / secrets | Critical | Secrets Manager + Key Vault | Encrypted, never in env vars or code |
| Internal service credentials | High | Secrets Manager / Key Vault | Rotated automatically |

---

## Compliance Requirements

| Standard | Scope | Key Controls |
|----------|-------|-------------|
| **PCI-DSS v4.0** | Any component that stores, processes, or transmits card data | Network segmentation, encryption, access control, logging, vulnerability management |
| **SOC 2 Type II** | All production infrastructure | Availability, confidentiality, change management, incident response |
| **GDPR** | EU user data (PII, behavioral) | Data minimization, right to erasure, breach notification within 72h, DPA agreements with processors |
| **FCA / Open Banking** | UK payment services | Strong Customer Authentication (SCA), secure communication standards |

---

## Attack Surface Analysis

### Network Boundaries
- Public internet — CloudFront/CDN edge (WAF-protected)
- DMZ — API Gateway tier (rate-limited, authenticated)
- Service mesh — internal EKS/AKS pod-to-pod (mTLS via Istio)
- Data tier — private subnets only, no public route, accessed via VPC endpoints
- Cross-cloud link — dedicated VPN tunnel between AWS VPC and Azure VNet

### API Endpoints (high-value targets)
- `POST /auth/login` — credential submission
- `POST /auth/mfa` — OTP verification
- `POST /payments/transfer` — fund movement
- `GET /accounts/{id}/transactions` — financial data read
- `POST /kyc/submit` — document upload
- `POST /admin/*` — privileged operations

### Data Storage Attack Surface
- RDS instances in private subnet, no public endpoint, encrypted at rest
- DynamoDB accessed only via VPC endpoint
- S3 buckets: block all public access, bucket policies deny non-VPC origins
- Redis: in-transit encryption enabled, auth token required, no public endpoint

---

## Threat Model

### Threat 1: SQL Injection (OWASP A03:2021 — Injection)
**Target:** Transaction query endpoints, account lookup APIs
**Attack Vector:** Malicious SQL in request parameters bypassing input validation
**Impact:** Unauthorized data read/modification, potential full DB compromise
**Likelihood:** Medium
**Mitigations:** Parameterized queries (ORM-enforced), WAF SQLi rule set, DB user least-privilege (read-only where applicable)

---

### Threat 2: Account Takeover via Credential Stuffing (OWASP A07:2021 — Identification & Auth Failures)
**Target:** `POST /auth/login`
**Attack Vector:** Automated use of breached credential lists
**Impact:** Unauthorized access to user accounts, fraudulent transactions
**Likelihood:** High (endemic in FinTech)
**Mitigations:** MFA enforcement, rate limiting on login endpoint, CAPTCHA after N failures, GuardDuty anomalous-login detection, AWS WAF bot control rule group

---

### Threat 3: Broken Object-Level Authorization (OWASP API Security #1)
**Target:** `GET /accounts/{id}/transactions`, `POST /payments/transfer`
**Attack Vector:** Authenticated user substitutes another user's ID in path/body
**Impact:** Unauthorized access to financial records or fund transfer
**Likelihood:** Medium
**Mitigations:** Server-side ownership check on every request, JWT sub claim validated against resource owner, automated BOLA test suite in CI

---

### Threat 4: Secrets Leakage via Source Code or Container Images (OWASP A02:2021 — Cryptographic Failures)
**Target:** GitHub repos, container registry
**Attack Vector:** API keys / DB credentials committed to code or baked into Docker layers
**Impact:** Full service compromise, data exfiltration
**Likelihood:** Medium
**Mitigations:** Pre-commit hooks (detect-secrets, gitleaks), all secrets sourced from Secrets Manager / Key Vault via Kubernetes External Secrets Operator, no env-var secrets in manifests

---

### Threat 5: Payment Fraud / Transaction Manipulation (FinTech-specific)
**Target:** `POST /payments/transfer`
**Attack Vector:** Attacker intercepts or replays valid transfer requests; or compromised session used to redirect funds
**Impact:** Direct financial loss
**Likelihood:** High
**Mitigations:** Idempotency keys, signed request payloads (HMAC), MFA step-up for high-value transfers, velocity checks, anomaly detection via GuardDuty + custom CloudWatch metric alarms

---

### Threat 6: Supply Chain Attack via Compromised Third-Party SDK (OWASP A06:2021 — Vulnerable & Outdated Components)
**Target:** KYC SDK, payment library dependencies
**Attack Vector:** Malicious package version published to npm/PyPI, consumed via CI without pin
**Impact:** Code execution in cluster, data exfiltration
**Likelihood:** Medium (rising industry trend)
**Mitigations:** Dependency pinning + hash verification, Trivy image scan in CI, Dependabot alerts, private artifact registry (ECR/ACR) with allowed-list

---

### Threat 7: Privilege Escalation via Misconfigured IAM / RBAC (OWASP A01:2021 — Broken Access Control)
**Target:** AWS IAM roles, Kubernetes RBAC, Azure AD service principals
**Attack Vector:** Overly permissive role assumptions; pod with cluster-admin binding
**Impact:** Lateral movement, full cloud account compromise
**Likelihood:** Medium
**Mitigations:** Least-privilege IAM (no wildcard actions), IRSA (IAM Roles for Service Accounts) per workload, AWS IAM Access Analyzer, Kubernetes RBAC audit, no cluster-admin in workloads

---

### Threat 8: Data Exfiltration via Compromised Container (OWASP A05:2021 — Security Misconfiguration)
**Target:** Pods with DB or secrets access
**Attack Vector:** RCE in application code allows attacker to read secrets mount or call metadata service
**Impact:** Mass credential theft, DB dump
**Likelihood:** Medium
**Mitigations:** Block IMDSv1 (require IMDSv2), read-only root filesystem on pods, network policies restricting egress to known destinations, GuardDuty EKS Runtime Monitoring, Falco for runtime anomaly detection

---

### Threat 9: KYC Document Exfiltration (FinTech-specific / GDPR)
**Target:** S3 bucket storing passport / ID scans
**Attack Vector:** Public S3 misconfiguration; or SSRF to fetch pre-signed URLs
**Impact:** Mass PII breach, regulatory fines (GDPR Article 83)
**Likelihood:** Low–Medium
**Mitigations:** S3 Block Public Access enforced by SCP, pre-signed URL TTL capped at 5 minutes, S3 Access Analyzer, SSRF protection via metadata service hardening and outbound WAF rules

---

### Threat 10: Man-in-the-Middle on Internal Service Mesh (OWASP A02:2021)
**Target:** Pod-to-pod traffic within EKS/AKS
**Attack Vector:** Compromised pod sniffs unencrypted east-west traffic
**Impact:** Session token theft, financial data interception
**Likelihood:** Low
**Mitigations:** Istio mTLS enforced in STRICT mode across all namespaces, certificate rotation via cert-manager, PeerAuthentication policy denying plaintext

---

## Risk Summary Matrix

| # | Threat | Likelihood | Impact | Risk Level |
|---|--------|-----------|--------|-----------|
| 1 | SQL Injection | Medium | Critical | High |
| 2 | Account Takeover (Credential Stuffing) | High | High | Critical |
| 3 | Broken Object-Level Authorization | Medium | High | High |
| 4 | Secrets Leakage | Medium | Critical | High |
| 5 | Payment Fraud / Transaction Manipulation | High | Critical | Critical |
| 6 | Supply Chain Attack | Medium | High | High |
| 7 | Privilege Escalation via IAM/RBAC | Medium | Critical | High |
| 8 | Container-Based Data Exfiltration | Medium | High | High |
| 9 | KYC Document Exfiltration | Low | Critical | High |
| 10 | MITM on Internal Service Mesh | Low | High | Medium |
