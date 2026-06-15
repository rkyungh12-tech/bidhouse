variable "location" {
  type        = string
  default     = "southeastasia" # 싱가포르 리전 코드명
  description = "Azure DR 리전 위치"
}

variable "prefix" {
  type        = string
  default     = "bidhouse-dr-v1" # 모든 자원 이름 앞에 붙을 접두사
  description = "리소스 네이밍 접두사"
}

variable "azure_mysql_admin_username" {
  description = "Azure MySQL administrator username stored in Key Vault"
  type        = string
  default     = "dbadmin"
}

variable "azure_app_image_tag" {
  description = "Azure Container Apps image tag. Placeholder is used before the first ACR push."
  type        = string
  default     = "placeholder"
}

variable "nat_gateway_public_ip" {
  type        = string
  description = "AWS NAT Gateway public IP for MySQL firewall"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "cognito_client_id" {
  description = "AWS Cognito App Client ID"
  type        = string
  default     = ""
}

variable "cognito_user_pool_id" {
  description = "AWS Cognito User Pool ID"
  type        = string
  default     = ""
}
variable "jwt_secret" {
  description = "JWT Secret from AWS Secrets Manager"
  type        = string
  sensitive   = true
  default     = ""
}