# ============================================================================
# Azure Container Apps user-assigned identity and RBAC
# ============================================================================

resource "azurerm_user_assigned_identity" "aca" {
  name                = "${var.prefix}-aca-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Environment = "DR"
    Project     = "BidHouse"
  }
}

resource "azurerm_role_assignment" "aca_key_vault_secrets_user" {
  scope                = azurerm_key_vault.dr.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aca_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
  principal_type       = "ServicePrincipal"
}

# CodeBuild logs in as this Terraform service principal and pushes the image.
resource "azurerm_role_assignment" "pipeline_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

resource "time_sleep" "wait_for_aca_rbac" {
  depends_on = [
    azurerm_role_assignment.aca_key_vault_secrets_user,
    azurerm_role_assignment.aca_acr_pull,
    azurerm_role_assignment.pipeline_acr_push
  ]

  create_duration = "30s"
}
