terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "network" {
  name     = "${local.name_prefix}-network-rg"
  location = var.location
  tags     = { Environment = var.environment, Project = var.project, ManagedBy = "terraform" }
}

# ---------------------------------------------------------------------------
# Virtual Network
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = { Environment = var.environment }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "azurerm_subnet" "public" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.101.0/24"]
}

resource "azurerm_subnet" "private_app" {
  name                 = "private-app-subnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "private_data" {
  name                 = "private-data-subnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.2.0/24"]
  service_endpoints    = ["Microsoft.Sql", "Microsoft.KeyVault", "Microsoft.Storage"]
}

# Dedicated subnet required by Azure Firewall (fixed name)
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.200.0/26"]
}

# ---------------------------------------------------------------------------
# Network Security Groups — default deny all inbound
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "public" {
  name                = "${local.name_prefix}-nsg-public"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  # Allow HTTPS inbound
  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Deny all other inbound (explicit — belt-and-suspenders over the implicit default)
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Environment = var.environment }
}

resource "azurerm_network_security_group" "private_app" {
  name                = "${local.name_prefix}-nsg-private-app"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  # HTTPS from within VNet only
  security_rule {
    name                       = "allow-https-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # SSH from bastion subnet only
  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_subnet.public.address_prefixes[0]
    destination_address_prefix = "*"
  }

  # Deny all other inbound
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Environment = var.environment }
}

resource "azurerm_network_security_group" "private_data" {
  name                = "${local.name_prefix}-nsg-private-data"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  # PostgreSQL from app subnet only
  security_rule {
    name                       = "allow-postgres-from-app"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = azurerm_subnet.private_app.address_prefixes[0]
    destination_address_prefix = "*"
  }

  # Redis from app subnet only
  security_rule {
    name                       = "allow-redis-from-app"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6379"
    source_address_prefix      = azurerm_subnet.private_app.address_prefixes[0]
    destination_address_prefix = "*"
  }

  # Deny all other inbound
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Environment = var.environment }
}

# NSG associations
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private_app" {
  subnet_id                 = azurerm_subnet.private_app.id
  network_security_group_id = azurerm_network_security_group.private_app.id
}

resource "azurerm_subnet_network_security_group_association" "private_data" {
  subnet_id                 = azurerm_subnet.private_data.id
  network_security_group_id = azurerm_network_security_group.private_data.id
}

# ---------------------------------------------------------------------------
# Azure Firewall — outbound traffic inspection and control
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "firewall" {
  name                = "${local.name_prefix}-fw-pip"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = { Environment = var.environment }
}

resource "azurerm_firewall" "main" {
  name                = "${local.name_prefix}-firewall"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = { Environment = var.environment }
}

# Firewall policy: allow outbound HTTPS only from private subnets
resource "azurerm_firewall_policy" "main" {
  name                = "${local.name_prefix}-fw-policy"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
}

resource "azurerm_firewall_policy_rule_collection_group" "outbound" {
  name               = "outbound-rules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100

  network_rule_collection {
    name     = "allow-outbound-https"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-https"
      protocols             = ["TCP"]
      source_addresses      = [azurerm_subnet.private_app.address_prefixes[0], azurerm_subnet.private_data.address_prefixes[0]]
      destination_addresses = ["*"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "allow-dns"
      protocols             = ["UDP"]
      source_addresses      = [var.vnet_cidr]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }
}

# Route table: force private subnet outbound through Azure Firewall
resource "azurerm_route_table" "private" {
  name                          = "${local.name_prefix}-rt-private"
  location                      = azurerm_resource_group.network.location
  resource_group_name           = azurerm_resource_group.network.name
  disable_bgp_route_propagation = true

  route {
    name                   = "force-outbound-to-fw"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }

  tags = { Environment = var.environment }
}

resource "azurerm_subnet_route_table_association" "private_app" {
  subnet_id      = azurerm_subnet.private_app.id
  route_table_id = azurerm_route_table.private.id
}

resource "azurerm_subnet_route_table_association" "private_data" {
  subnet_id      = azurerm_subnet.private_data.id
  route_table_id = azurerm_route_table.private.id
}

# ---------------------------------------------------------------------------
# Network Watcher + Flow Logs (audit trail)
# ---------------------------------------------------------------------------
resource "azurerm_network_watcher" "main" {
  name                = "${local.name_prefix}-network-watcher"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_storage_account" "flow_logs" {
  name                     = "${replace(local.name_prefix, "-", "")}flowlogs"
  resource_group_name      = azurerm_resource_group.network.name
  location                 = azurerm_resource_group.network.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = { Environment = var.environment }
}

resource "azurerm_network_watcher_flow_log" "app" {
  name                 = "${local.name_prefix}-flow-log-app"
  network_watcher_name = azurerm_network_watcher.main.name
  resource_group_name  = azurerm_resource_group.network.name
  network_security_group_id = azurerm_network_security_group.private_app.id
  storage_account_id   = azurerm_storage_account.flow_logs.id
  enabled              = true

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = false
    workspace_id          = ""
    workspace_region      = var.location
    workspace_resource_id = ""
  }
}
