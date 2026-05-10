terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    # Populated via -backend-config at init time or backend.hcl
    # bucket         = "clearpay-tfstate-<account-id>"
    # key            = "network/<environment>/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "clearpay-tfstate-lock"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}
}

module "aws_network" {
  source = "./aws"

  environment           = var.environment
  project               = var.project
  vpc_cidr              = var.aws_vpc_cidr
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
}

module "azure_network" {
  source = "./azure"

  environment    = var.environment
  project        = var.project
  location       = var.azure_location
  vnet_cidr      = var.azure_vnet_cidr
}
