terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

locals {
  entra_prefix = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Security Groups (Entra ID)
# ---------------------------------------------------------------------------
resource "azuread_group" "platform_engineers" {
  display_name     = "${local.entra_prefix}-platform-engineers"
  security_enabled = true
  description      = "Platform engineers with contributor-level access"
}

resource "azuread_group" "security_auditors" {
  display_name     = "${local.entra_prefix}-security-auditors"
  security_enabled = true
  description      = "Read-only security audit access"
}

resource "azuread_group" "app_developers" {
  display_name     = "${local.entra_prefix}-app-developers"
  security_enabled = true
  description      = "Application developers — scoped to dev/staging resource groups"
}

# ---------------------------------------------------------------------------
# Azure Role Assignments — least-privilege
# ---------------------------------------------------------------------------

# Platform engineers: Contributor on network + compute RGs, NOT on Key Vault
resource "azurerm_role_assignment" "platform_engineers_network" {
  scope                = var.network_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.platform_engineers.object_id
}

resource "azurerm_role_assignment" "platform_engineers_compute" {
  scope                = var.compute_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.platform_engineers.object_id
}

# Security auditors: Reader on subscription, Security Reader on Security Center
resource "azurerm_role_assignment" "security_auditors_reader" {
  scope                = var.subscription_id
  role_definition_name = "Reader"
  principal_id         = azuread_group.security_auditors.object_id
}

resource "azurerm_role_assignment" "security_auditors_security_reader" {
  scope                = var.subscription_id
  role_definition_name = "Security Reader"
  principal_id         = azuread_group.security_auditors.object_id
}

# App developers: scoped Contributor on dev resource group only
resource "azurerm_role_assignment" "app_developers_dev" {
  count                = var.environment == "dev" ? 1 : 0
  scope                = var.compute_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.app_developers.object_id
}

# ---------------------------------------------------------------------------
# Service Principal for CI/CD (GitHub Actions federated identity)
# ---------------------------------------------------------------------------
resource "azuread_application" "cicd" {
  display_name = "${local.entra_prefix}-cicd-sp"
}

resource "azuread_service_principal" "cicd" {
  client_id = azuread_application.cicd.client_id
}

resource "azuread_application_federated_identity_credential" "cicd_github" {
  application_id = azuread_application.cicd.id
  display_name   = "github-actions"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"
}

# CI/CD SP gets Contributor on compute RG + AcrPush on container registry
resource "azurerm_role_assignment" "cicd_compute" {
  scope                = var.compute_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cicd.object_id
}

resource "azurerm_role_assignment" "cicd_acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.cicd.object_id
}

# ---------------------------------------------------------------------------
# Custom Role — Key Vault secrets read-only for app workloads
# ---------------------------------------------------------------------------
resource "azurerm_role_definition" "kv_secrets_reader" {
  name        = "${local.entra_prefix}-kv-secrets-reader"
  scope       = var.subscription_id
  description = "Read Key Vault secrets only — no key or certificate access"

  permissions {
    actions = [
      "Microsoft.KeyVault/vaults/secrets/read"
    ]
    not_actions = []
  }

  assignable_scopes = [var.subscription_id]
}
