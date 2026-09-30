# ============================================================================
# Azure Key Vault: DR database and application runtime secrets
# ============================================================================

data "azurerm_client_config" "current" {}

resource "random_password" "mysql_admin" {
  length           = 24
  special          = true
  override_special = "!#%_-"
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "initial_admin_password" {
  length           = 24
  special          = true
  override_special = "!#%_-"
}

resource "random_password" "azure_vm_admin" {
  length           = 24
  special          = true
  override_special = "!#%_-"
}

resource "azurerm_key_vault" "dr" {
  name                       = "biddrkv${random_string.global_suffix.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = {
    Environment = "DR"
    Project     = "BidHouse"
  }
}

resource "azurerm_role_assignment" "terraform_key_vault_secret_officer" {
  scope                = azurerm_key_vault.dr.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

resource "time_sleep" "wait_for_terraform_key_vault_rbac" {
  depends_on      = [azurerm_role_assignment.terraform_key_vault_secret_officer]
  create_duration = "30s"
}

resource "azurerm_key_vault_secret" "mysql_admin_username" {
  name         = "mysql-admin-username"
  value        = var.azure_mysql_admin_username
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = random_password.mysql_admin.result
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = var.jwt_secret != "" ? var.jwt_secret : random_password.jwt_secret.result
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "initial_admin_username" {
  name         = "initial-admin-username"
  value        = "admin"
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "initial_admin_password" {
  name         = "initial-admin-password"
  value        = random_password.initial_admin_password.result
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "initial_admin_email" {
  name         = "initial-admin-email"
  value        = "admin@bidhouse.local"
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "azure_vm_admin_password" {
  name         = "azure-vm-admin-password"
  value        = random_password.azure_vm_admin.result
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}


resource "azurerm_key_vault_secret" "aws_access_key" {
  name         = "aws-access-key-id"
  value        = var.aws_access_key_id  # 실제 값 대신 변수로!
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

resource "azurerm_key_vault_secret" "aws_secret_key" {
  name         = "aws-secret-access-key"
  value        = var.aws_secret_access_key # 실제 값 대신 변수로!
  key_vault_id = azurerm_key_vault.dr.id
  depends_on   = [time_sleep.wait_for_terraform_key_vault_rbac]
}

output "azure_key_vault_name" {
  value       = azurerm_key_vault.dr.name
  description = "Azure DR Key Vault name"
}