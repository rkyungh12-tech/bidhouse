# Globally unique suffix for Azure resources whose names are global.
resource "random_string" "global_suffix" {
  length  = 6
  upper   = false
  special = false
}
