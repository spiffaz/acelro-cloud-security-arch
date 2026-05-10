# Azure Firewall policy rules — extends the base policy created in vnet.tf
# Azure WAF (Application Gateway WAF) is not configured in this file.

resource "azurerm_firewall_policy_rule_collection_group" "security" {
  name               = "security-rules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 200

  # Block known malicious outbound destinations
  network_rule_collection {
    name     = "deny-risky-outbound"
    priority = 100
    action   = "Deny"

    rule {
      name                  = "deny-tor-exits"
      protocols             = ["TCP", "UDP"]
      source_addresses      = [var.vnet_cidr]
      destination_addresses = ["TorExitNode"]
      destination_ports     = ["*"]
    }
  }

  # Allow inter-service traffic within private subnets
  network_rule_collection {
    name     = "allow-internal"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-app-to-data"
      protocols             = ["TCP"]
      source_addresses      = ["10.1.1.0/24"]
      destination_addresses = ["10.1.2.0/24"]
      destination_ports     = ["5432", "6379"]
    }

    rule {
      name                  = "allow-app-to-keyvault"
      protocols             = ["TCP"]
      source_addresses      = ["10.1.1.0/24"]
      destination_addresses = ["AzureKeyVault"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "allow-app-to-acr"
      protocols             = ["TCP"]
      source_addresses      = ["10.1.1.0/24"]
      destination_addresses = ["AzureContainerRegistry"]
      destination_ports     = ["443"]
    }
  }

  # Application rules — FQDN-based allow list for egress
  application_rule_collection {
    name     = "allow-egress-fqdns"
    priority = 300
    action   = "Allow"

    rule {
      name             = "allow-microsoft-services"
      source_addresses = [var.vnet_cidr]
      protocols {
        type = "Https"
        port = 443
      }
      target_fqdns = [
        "*.azure.com",
        "*.microsoft.com",
        "*.azurecr.io",
        "mcr.microsoft.com"
      ]
    }

    rule {
      name             = "allow-stripe-api"
      source_addresses = ["10.1.1.0/24"]
      protocols {
        type = "Https"
        port = 443
      }
      target_fqdns = ["api.stripe.com"]
    }
  }
}

# Diagnostic settings — send firewall logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "${var.project}-${var.environment}-fw-diag"
  target_resource_id         = azurerm_firewall.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
