# Encryption Configuration

This document covers encryption at rest and in transit for all data stores in the ClearPay FinTech platform across AWS and Azure.

## Summary

| Store | Cloud | Encryption at Rest | Key | TLS Enforced |
|-------|-------|--------------------|-----|-------------|
| Aurora PostgreSQL | AWS | SSE — KMS CMK | `alias/clearpay-<env>-rds` | Yes (`rds.force_ssl=1`, min TLS 1.2) |
| DynamoDB | AWS | SSE — KMS CMK | `alias/clearpay-<env>-dynamodb` | Yes (AWS SDK enforces HTTPS) |
| S3 (KYC documents) | AWS | SSE-KMS CMK | `alias/clearpay-<env>-s3` | Yes (bucket policy denies non-TLS) |
| Azure SQL | Azure | TDE — Key Vault CMK | `sql-cmk-<env>` in Key Vault | Yes (minimum TLS 1.2 on server) |
| Cosmos DB | Azure | CMK via Key Vault | `cosmos-cmk-<env>` in Key Vault | Yes (HTTPS only, Azure-enforced) |

---

## AWS

### KMS Key Strategy

Three separate KMS keys are provisioned (one per service) so that a key compromise is bounded to a single service, key usage logs are cleanly separated in CloudTrail, and key policies can be scoped independently.

| Key Alias | Service | Rotation | Deletion Window |
|-----------|---------|----------|----------------|
| `clearpay-<env>-rds` | Aurora PostgreSQL | Automatic, annual | 30 days |
| `clearpay-<env>-dynamodb` | DynamoDB | Automatic, annual | 30 days |
| `clearpay-<env>-s3` | S3 (KYC bucket) | Automatic, annual | 30 days |

Key policies follow least-privilege: only the service principal and the application IAM role are granted `kms:Decrypt` / `kms:GenerateDataKey`. The root account retains administrative access for break-glass scenarios.

### Aurora PostgreSQL

Encryption at rest is enabled at the cluster level via `storage_encrypted = true` and `kms_key_id`. Encryption cannot be added to an existing unencrypted cluster — it must be set at creation time.

SSL is enforced at the parameter group level:

```
rds.force_ssl             = 1
ssl_min_protocol_version  = TLSv1.2
```

Connection string with SSL validation:

```
postgresql://user:pass@host:5432/dbname?sslmode=verify-full&sslrootcert=/path/to/rds-ca-bundle.pem
```

The CA bundle is available at: `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`

The master password is managed by RDS (`manage_master_user_password = true`), which rotates it in Secrets Manager automatically.

### DynamoDB

Server-side encryption uses a customer-managed KMS key (`SSEType = KMS`). All DynamoDB traffic to AWS endpoints is HTTPS by default — the AWS SDK enforces this and there is no opt-out path.

Point-in-time recovery (PITR) is enabled on all tables, providing continuous backups with 35-day recovery window.

### S3 (KYC Documents)

Default encryption uses `aws:kms` with the `clearpay-<env>-s3` key and `BucketKeyEnabled = true` (reduces KMS API call cost by ~99% for high-volume buckets).

A bucket policy explicitly denies any request where `aws:SecureTransport` is `false`, making TLS non-optional regardless of client configuration:

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```

---

## Azure

### Key Vault Configuration

A single Key Vault per environment holds all CMKs. The vault is `premium` SKU (HSM-backed keys) with:

- Public network access disabled
- Private endpoint required for access
- Soft delete: 90 days
- Purge protection: enabled (required for CMK use with Azure SQL and Cosmos DB)

Key rotation policy (both keys):

| Environment | Key lifetime | Auto-rotate before expiry |
|-------------|-------------|--------------------------|
| prod | 90 days | 30 days before expiry |
| dev / staging | 180 days | 30 days before expiry |

### Azure SQL Database

Transparent Data Encryption (TDE) uses a Key Vault CMK (`sql-cmk-<env>`). The server is configured with:

- `minimum_tls_version = "1.2"` — enforced at the server level, all client connections must use TLS 1.2+
- Azure AD-only authentication (`azuread_authentication_only = true`) — SQL login disabled
- No public firewall rules — traffic routes through private endpoint only
- `auto_rotation_enabled = true` on the TDE protector — when the Key Vault key rotates, SQL re-encrypts the DEK automatically

Connection string (Azure AD token auth, TLS enforced by driver):

```
Server=tcp:<server>.database.windows.net,1433;Database=<db>;Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;
```

### Cosmos DB

CMK is set at account creation time via `key_vault_key_id` using the versionless key URI. Cosmos DB uses the account's system-assigned managed identity to access the Key Vault key.

- Public network access: disabled
- All traffic via private endpoint
- HTTPS is the only supported protocol (HTTP is unavailable for Cosmos DB)

---

## Encryption in Transit — Application Layer

All inter-service communication enforces TLS 1.2+:

| Path | Mechanism |
|------|-----------|
| Client to CDN/WAF | TLS 1.2+ (enforced at CloudFront / Azure Front Door) |
| CDN to API Gateway | TLS 1.2+ |
| API Gateway to EKS/AKS | TLS via Istio mTLS (STRICT mode) |
| Pod to pod (service mesh) | mTLS via Istio — plaintext rejected by PeerAuthentication policy |
| App to RDS | `sslmode=verify-full` with RDS CA bundle |
| App to Azure SQL | `Encrypt=True;TrustServerCertificate=False` |
| App to DynamoDB / Cosmos DB | HTTPS enforced by SDK |
| App to Secrets Manager / Key Vault | HTTPS via VPC endpoint / private endpoint |

Certificate validation (`verify-full` / `TrustServerCertificate=False`) is mandatory — self-signed or unverified certificates will cause connection failure, not a silent downgrade.

---

## Compliance Mapping

| Requirement | Control |
|-------------|---------|
| PCI-DSS 3.4 — render PAN unreadable | DynamoDB + RDS CMK encryption; card PANs never stored (tokenized via Stripe Vault) |
| PCI-DSS 4.1 — encrypt transmission over open networks | TLS 1.2+ enforced on all ingress and egress paths |
| GDPR Art. 32 — appropriate technical measures | Encryption at rest (CMK) + in transit (TLS) + key rotation |
| SOC 2 CC6.1 — logical access to data | CMK key policies restrict decrypt to app role only |
