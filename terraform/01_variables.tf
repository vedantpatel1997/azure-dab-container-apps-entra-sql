variable "subscription_id" {
  type    = string
  default = "6a3bb170-5159-4bff-860b-aa74fb762697"
}

variable "tenant_id" {
  type    = string
  default = "be945e7a-2e17-4b44-926f-512e85873eec"
}

variable "location" {
  type    = string
  default = "westus3"
}

variable "name_prefix" {
  type    = string
  default = "dabsecure"
}

variable "sql_database_name" {
  type    = string
  default = "dabdemo"
}

variable "sql_admin_login" {
  type    = string
  default = "sqladminuser"
}

variable "sql_admin_password" {
  type      = string
  default   = null
  sensitive = true
}

variable "allowed_ip_addresses" {
  type    = map(string)
  default = {}
}
