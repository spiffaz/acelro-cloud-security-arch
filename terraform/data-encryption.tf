# Data protection — encryption at rest and in transit for all data stores.
# Applies to both AWS (RDS, DynamoDB, S3) and Azure (SQL, Cosmos DB, Key Vault).

# ---------------------------------------------------------------------------
# AWS KMS Keys (one per service, enables independent rotation + audit)
# ---------------------------------------------------------------------------
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS/Aurora encryption — ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowRDSService"
        Effect = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
        Resource = "*"
      },
      {
        Sid    = "AllowAppRole"
        Effect = "Allow"
        Principal = { AWS = var.app_role_arn }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })

  tags = { Environment = var.environment, Service = "rds" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for DynamoDB encryption — ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowDynamoDBService"
        Effect = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
        Resource = "*"
      },
      {
        Sid    = "AllowAppRole"
        Effect = "Allow"
        Principal = { AWS = var.app_role_arn }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })

  tags = { Environment = var.environment, Service = "dynamodb" }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project}-${var.environment}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 (KYC documents) — ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Environment = var.environment, Service = "s3" }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# ---------------------------------------------------------------------------
# RDS Aurora PostgreSQL — encrypted, SSL enforced
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "postgres_ssl" {
  name_prefix = "${var.project}-${var.environment}-pg-ssl-"
  family      = "aurora-postgresql15"
  description = "Force SSL connections to Aurora PostgreSQL"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "ssl_min_protocol_version"
    value        = "TLSv1.2"
    apply_method = "immediate"
  }

  tags = { Environment = var.environment }
}

resource "aws_rds_cluster_parameter_group" "postgres_ssl" {
  name_prefix = "${var.project}-${var.environment}-cluster-pg-ssl-"
  family      = "aurora-postgresql15"
  description = "Cluster-level SSL enforcement"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  tags = { Environment = var.environment }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${var.project}-${var.environment}-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  database_name          = var.db_name
  master_username        = var.db_master_username
  manage_master_user_password = true  # Stores master password in Secrets Manager automatically

  # Encryption at rest
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Networking — private subnets only, no public access
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.data_sg_id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.postgres_ssl.name

  # Backups
  backup_retention_period      = var.environment == "prod" ? 30 : 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"

  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Environment = var.environment }
}

resource "aws_rds_cluster_instance" "main" {
  count = var.environment == "prod" ? 2 : 1

  identifier         = "${var.project}-${var.environment}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.environment == "prod" ? "db.r6g.large" : "db.t4g.medium"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_parameter_group_name      = aws_db_parameter_group.postgres_ssl.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  tags = { Environment = var.environment }
}

resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project}-${var.environment}-db-subnet-"
  subnet_ids  = var.private_subnet_ids

  tags = { Environment = var.environment }
}

# ---------------------------------------------------------------------------
# DynamoDB — customer-managed KMS key, point-in-time recovery
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project}-${var.environment}-transactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"
  range_key    = "created_at"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "user_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  # Encryption with customer-managed KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Environment = var.environment }
}

# ---------------------------------------------------------------------------
# S3 Bucket — KYC documents, SSE-KMS, enforced TLS
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "kyc_documents" {
  bucket_prefix = "${var.project}-${var.environment}-kyc-"

  tags = { Environment = var.environment, DataClassification = "critical" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kyc" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "kyc" {
  bucket                  = aws_s3_bucket.kyc_documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "kyc" {
  bucket = aws_s3_bucket.kyc_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Deny any request not using TLS
resource "aws_s3_bucket_policy" "kyc_enforce_tls" {
  bucket = aws_s3_bucket.kyc_documents.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.kyc_documents.arn,
          "${aws_s3_bucket.kyc_documents.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# Lifecycle: delete non-current versions after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "kyc" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# Azure Key Vault
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                        = "${var.project}-${var.environment}-kv"
  location                    = var.azure_location
  resource_group_name         = var.azure_compute_rg_name
  tenant_id                   = var.azure_tenant_id
  sku_name                    = "premium"  # HSM-backed keys

  # Soft delete and purge protection required for CMK use
  soft_delete_retention_days  = 90
  purge_protection_enabled    = true

  # Disable public network access — accessed only via private endpoint
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []
    virtual_network_subnet_ids = [var.azure_private_app_subnet_id]
  }

  tags = { Environment = var.environment }
}

# Key rotation policy — 90-day auto-rotation in prod, 180-day in non-prod
resource "azurerm_key_vault_key" "sql_cmk" {
  name         = "sql-cmk-${var.environment}"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = var.environment == "prod" ? "P90D" : "P180D"
    notify_before_expiry = "P29D"
  }
}

resource "azurerm_key_vault_key" "cosmos_cmk" {
  name         = "cosmos-cmk-${var.environment}"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = var.environment == "prod" ? "P90D" : "P180D"
    notify_before_expiry = "P29D"
  }
}

# ---------------------------------------------------------------------------
# Azure SQL Database — TDE with CMK, TLS 1.2 minimum
# ---------------------------------------------------------------------------
resource "azurerm_mssql_server" "main" {
  name                         = "${var.project}-${var.environment}-sqlsrv"
  resource_group_name          = var.azure_compute_rg_name
  location                     = var.azure_location
  version                      = "12.0"
  administrator_login          = var.azure_sql_admin_username
  administrator_login_password = var.azure_sql_admin_password

  minimum_tls_version = "1.2"

  # Azure AD-only auth
  azuread_administrator {
    login_username              = "sql-admins"
    object_id                   = var.azure_sql_admin_group_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = { Environment = var.environment }
}

resource "azurerm_mssql_server_transparent_data_encryption" "main" {
  server_id             = azurerm_mssql_server.main.id
  key_vault_key_id      = azurerm_key_vault_key.sql_cmk.id
  auto_rotation_enabled = true
}

resource "azurerm_mssql_database" "main" {
  name      = "${var.project}-${var.environment}-db"
  server_id = azurerm_mssql_server.main.id
  sku_name  = var.environment == "prod" ? "GP_Gen5_4" : "GP_Gen5_2"

  transparent_data_encryption_enabled = true

  # Auditing
  threat_detection_policy {
    state                      = "Enabled"
    email_account_admins       = true
    retention_days             = 90
  }

  tags = { Environment = var.environment }
}

# Block all public access — traffic routes through private endpoint only
resource "azurerm_mssql_firewall_rule" "deny_public" {
  name             = "DenyAllPublic"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ---------------------------------------------------------------------------
# Azure Cosmos DB — CMK encryption, private endpoint
# ---------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.project}-${var.environment}-cosmos"
  location            = var.azure_location
  resource_group_name = var.azure_compute_rg_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Customer-managed key encryption
  key_vault_key_id = azurerm_key_vault_key.cosmos_cmk.versionless_id

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.azure_location
    failover_priority = 0
  }

  # Network: deny public access
  public_network_access_enabled         = false
  is_virtual_network_filter_enabled     = true
  network_acl_bypass_for_azure_services = false

  identity {
    type = "SystemAssigned"
  }

  tags = { Environment = var.environment }
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "${var.project}-${var.environment}"
  resource_group_name = var.azure_compute_rg_name
  account_name        = azurerm_cosmosdb_account.main.name
}
