variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "project" {
  description = "Project name used in resource tags and names"
  type        = string
  default     = "clearpay"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for the AWS VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azure_vnet_cidr" {
  description = "CIDR block for the Azure VNet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "bastion_allowed_cidrs" {
  description = "CIDRs permitted to SSH to the bastion host"
  type        = list(string)
  default     = []
}

# Provided by CI/CD — never committed to source control
variable "aws_account_id" {
  description = "AWS account ID for backend bucket naming"
  type        = string
  sensitive   = true
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

# IAM / Entra ID
variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
  default     = ""
}

variable "eks_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster (without https://)"
  type        = string
  default     = ""
}

variable "app_namespace" {
  description = "Kubernetes namespace for the application service account"
  type        = string
  default     = "default"
}

variable "app_service_account" {
  description = "Kubernetes service account name for the application"
  type        = string
  default     = "app"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for app data encryption"
  type        = string
  default     = ""
}

variable "kyc_bucket_name" {
  description = "S3 bucket name for KYC document storage"
  type        = string
  default     = ""
}

variable "security_auditor_principal_arn" {
  description = "ARN of the principal allowed to assume the security auditor role"
  type        = string
  default     = ""
}

variable "github_org" {
  description = "GitHub organisation name for OIDC trust"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name for OIDC trust"
  type        = string
  default     = ""
}

# WAF
variable "waf_log_destination_arn" {
  description = "ARN of the Kinesis Firehose delivery stream for WAF logs"
  type        = string
  default     = ""
}

# Azure resource scopes
variable "subscription_id" {
  description = "Azure subscription resource ID (/subscriptions/...)"
  type        = string
  default     = ""
}

variable "network_resource_group_id" {
  description = "Resource ID of the Azure network resource group"
  type        = string
  default     = ""
}

variable "compute_resource_group_id" {
  description = "Resource ID of the Azure compute resource group"
  type        = string
  default     = ""
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for diagnostic settings"
  type        = string
  default     = ""
}
