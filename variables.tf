variable "resource_group_location" {
  default     = "northeurope"
  description = "Location of the resource group."
}

variable "resource_group_name_prefix" {
  default     = "rg"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

# --- VPNGW1 ----

variable "vnet1_cidr" {
  default = ["10.4.0.0/16"]
  description = "azure vnet cidr"
}
variable "vnet1_subnet_address" {
  default = ["10.4.1.0/24"]
}
variable "vnet1_gateway_subnet_address" {
  default = ["10.4.3.0/27"]
}
variable "vnet1_bastion_subnet_address" {
  default = ["10.4.4.0/24"]
}
variable "vpngw_bgp_peering_address" {
  default = "10.4.3.30"
  description = "Enter this value after creating vpn gateway, as of now keep default"
}



# --- VPNGW2 ----
variable "vnet2_cidr" {
  default = ["10.6.0.0/16"]
  description = "azure vnet cidr"
}
variable "vnet2_subnet_address" {
  default = ["10.6.1.0/24"]
}
variable "vnet2_gateway_subnet_address" {
  default = ["10.6.3.0/27"]
}
variable "vnet2_bastion_subnet_address" {
  default = ["10.6.4.0/24"]
}
variable "vpngw2_bgp_peering_address" {
  default = "10.6.3.30"
  description = "Enter this value after creating vpn gateway, as of now keep default"
}
