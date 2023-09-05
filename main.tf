# Generate Random resource_group name
resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

# Create virtual network
resource "azurerm_virtual_network" "vnet1_work" {
  name                = "Vnet1"
  address_space       = var.vnet1_cidr
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create public subnet
resource "azurerm_subnet" "vnet_subnet" {
  name                 = "${azurerm_virtual_network.vnet1_work.name}_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1_work.name
  address_prefixes     = var.vnet1_subnet_address
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "SecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "InternetAccess"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "RDP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create public IPs
resource "azurerm_public_ip" "public_ip" {
  name                = "Vm1_public_ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}
# Create network interface
resource "azurerm_network_interface" "public_nic" {
  name                = "NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "nic_configuration"
    subnet_id                     = azurerm_subnet.vnet_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Connect the security group to the network interface (NIC)
resource "azurerm_network_interface_security_group_association" "connect_nsg_to_nic" {
  network_interface_id      = azurerm_network_interface.public_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create virtual machine
resource "azurerm_windows_virtual_machine" "vm" {
  name                  = "${var.resource_group_location}-Vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.public_nic.id]
  size                  = "Standard_DS1_v2"
  admin_username                  = "demousr"
  admin_password                  = "Password@123"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm_extension_install_iis" {
  name                       = "vm_extension_install_iis"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.9"
  auto_upgrade_minor_version = true
  settings = <<SETTINGS
    {
        "commandToExecute":"powershell -ExecutionPolicy Unrestricted Add-WindowsFeature Web-Server; powershell -ExecutionPolicy Unrestricted Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.html\" -Value $($env:computername)"
    }
SETTINGS
}

#create azure GatewaySubnet
resource "azurerm_subnet" "vnet_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1_work.name
  address_prefixes     = var.vnet1_gateway_subnet_address
}
resource "azurerm_public_ip" "Vnet1_GatewaySubnetPublicIp" {
  name                = "Vnet1_GatewaySubnetPublicIp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

#create azure virtual network gateway 
resource "azurerm_virtual_network_gateway" "Vnet1_VirtualNetworkGateway" {
  name                = "${azurerm_virtual_network.vnet1_work.name}-VPNGW"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "Standard"
  enable_bgp          = true
  
  ip_configuration {
    name                          = "vnet1GatewayConfig"
    public_ip_address_id          = azurerm_public_ip.Vnet1_GatewaySubnetPublicIp.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vnet_gateway_subnet.id
  }
  bgp_settings {
    asn                           = 65010
  }
}

# Local network Gateway
resource "azurerm_local_network_gateway" "VPN1GW_LGW-pointing-to-VPN2GW" {
  name                = "VPN1GW_LGW-pointing-to-VPN2GW"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = azurerm_public_ip.Vnet2_GatewaySubnetPublicIp.ip_address

  bgp_settings        {
    asn                           = 65020
    # bgp_peering_address           = azurerm_virtual_network_gateway.Vnet2_VirtualNetworkGateway.private_ip_address_enabled
    bgp_peering_address           = var.vpngw2_bgp_peering_address
    # bgp_peering_address           = "10.6.3.30"
  }
  depends_on               = [azurerm_public_ip.Vnet2_GatewaySubnetPublicIp]
}

resource "azurerm_virtual_network_gateway_connection" "lGW-VPN1GW-connection" {
  name                = "lGW-VPN1GW-connection"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_bgp          = true

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.Vnet1_VirtualNetworkGateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.VPN1GW_LGW-pointing-to-VPN2GW.id

  shared_key = "abc@143"
}

# Azure Bastion host
resource "azurerm_subnet" "AzureBastionSubnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1_work.name
  address_prefixes     = var.vnet1_bastion_subnet_address
}

resource "azurerm_public_ip" "bastion_pip" {
  name                = "bastion_pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "BastionHost" {
  name                = "BastionHost"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                 = "bastion_pip_config"
    subnet_id            = azurerm_subnet.AzureBastionSubnet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}

##### Vnet 2


# Create virtual network
resource "azurerm_virtual_network" "vnet2_work" {
  name                = "Vnet2"
  address_space       = var.vnet2_cidr
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create public subnet
resource "azurerm_subnet" "vnet2_subnet" {
  name                 = "${azurerm_virtual_network.vnet2_work.name}_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet2_work.name
  address_prefixes     = var.vnet2_subnet_address
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "Vnet2_nsg" {
  name                = "Vnet2_SecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "InternetAccess"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "RDP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create public IPs
resource "azurerm_public_ip" "vnet2_public_ip" {
  name                = "Vm2_public_ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}
# Create network interface
resource "azurerm_network_interface" "vnet2_public_nic" {
  name                = "vnet2_public_nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vnet2_nic_configuration"
    subnet_id                     = azurerm_subnet.vnet2_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vnet2_public_ip.id
  }
}

# Connect the security group to the network interface (NIC)
resource "azurerm_network_interface_security_group_association" "vm2_connect_nsg_to_nic" {
  network_interface_id      = azurerm_network_interface.vnet2_public_nic.id
  network_security_group_id = azurerm_network_security_group.Vnet2_nsg.id
}

# Create virtual machine
resource "azurerm_windows_virtual_machine" "vm2" {
  name                  = "${var.resource_group_location}-Vm2"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vnet2_public_nic.id]
  size                  = "Standard_DS1_v2"
  admin_username                  = "demousr"
  admin_password                  = "Password@123"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm2_extension_install_iis" {
  name                       = "vm_extension_install_iis"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm2.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.9"
  auto_upgrade_minor_version = true
  settings = <<SETTINGS
    {
        "commandToExecute":"powershell -ExecutionPolicy Unrestricted Add-WindowsFeature Web-Server; powershell -ExecutionPolicy Unrestricted Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.html\" -Value $($env:computername)"
    }
SETTINGS
}

#create azure GatewaySubnet
resource "azurerm_subnet" "vnet2_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet2_work.name
  address_prefixes     = var.vnet2_gateway_subnet_address
}
resource "azurerm_public_ip" "Vnet2_GatewaySubnetPublicIp" {
  name                = "VPN2_GatewaySubnetPublicIp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

#create azure virtual network gateway 
resource "azurerm_virtual_network_gateway" "Vnet2_VirtualNetworkGateway" {
  name                = "${azurerm_virtual_network.vnet2_work.name}-VPNGW"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "Standard"
  enable_bgp          = true
  
  ip_configuration {
    name                          = "vnet2GatewayConfig"
    public_ip_address_id          = azurerm_public_ip.Vnet2_GatewaySubnetPublicIp.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vnet2_gateway_subnet.id
  }
  bgp_settings {
    asn                           = 65020
  }
}

# Local network Gateway
resource "azurerm_local_network_gateway" "lgw2-pointing-to-VPNGW1" {
  name                = "lgw2-pointing-to-VPNGW1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = azurerm_public_ip.Vnet1_GatewaySubnetPublicIp.ip_address
  bgp_settings        {
    asn                           = 65010
    bgp_peering_address           = var.vpngw_bgp_peering_address
    # bgp_peering_address           = "10.4.3.30"
    
  }
  depends_on               = [azurerm_public_ip.Vnet1_GatewaySubnetPublicIp]
}

resource "azurerm_virtual_network_gateway_connection" "site1_connection" {
  name                = "lGW2-VPNGW2site1_connection"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_bgp          = true

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.Vnet2_VirtualNetworkGateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.lgw2-pointing-to-VPNGW1.id

  shared_key = "abc@143"
}
# Azure Bastion host
# resource "azurerm_subnet" "Vnet2_AzureBastionSubnet" {
#   name                 = "AzureBastionSubnet"
#   resource_group_name = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet2_work.name
#   address_prefixes     = var.vnet2_bastion_subnet_address
# }

# resource "azurerm_public_ip" "vnet2_bastion_pip" {
#   name                = "vnet2_bastion_pip"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

# resource "azurerm_bastion_host" "Vnet2_BastionHost" {
#   name                = "Vnet2_BastionHost"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name

#   ip_configuration {
#     name                 = "bastion_pip_config"
#     subnet_id            = azurerm_subnet.Vnet2_AzureBastionSubnet.id
#     public_ip_address_id = azurerm_public_ip.vnet2_bastion_pip.id
#   }
# }