terraform {
  required_providers {
    azurerm = {
        source  = "hashicorp/azurerm"
        version = ">= 3.0.1"
    }
  }
}

provider "azurerm" {
    skip_provider_registration = true
    features {
    }
}

resource "azurerm_resource_group" "terraformazurenginx" {
  name     = "terraformazurenginx"
  location = "eastus"
}

resource "azurerm_virtual_network" "virtualnetwork" {
  name                = "virtualnetwork"
  location            = azurerm_resource_group.terraformazurenginx.location
  resource_group_name = azurerm_resource_group.terraformazurenginx.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.terraformazurenginx.name
  virtual_network_name = azurerm_virtual_network.virtualnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "publicip" {
  name                = "publicip"
  resource_group_name = azurerm_resource_group.terraformazurenginx.name
  location            = azurerm_resource_group.terraformazurenginx.location
  allocation_method   = "Static"

  tags = {
    turma       = "as04"
    disciplina  = "infra cloud"
    professor   = "João"
    aluno       = "Jéferson"
    environment = "Test"
  }
}

resource "azurerm_network_interface" "terraformazurenginx-networkinterface" {
  name                = "terraformazurenginx-networkinterface"
  location            = azurerm_resource_group.terraformazurenginx.location
  resource_group_name = azurerm_resource_group.terraformazurenginx.name

  ip_configuration {
    name                            = "internal"
    subnet_id                       = azurerm_subnet.subnet.id
    private_ip_address_allocation   = "Dynamic"
    public_ip_address_id            = azurerm_public_ip.publicip.id
  }
}

resource "azurerm_network_security_group" "terraformazurenginx-ng" {
  name                = "terraformazurenginx-ng"
  location            = azurerm_resource_group.terraformazurenginx.location
  resource_group_name = azurerm_resource_group.terraformazurenginx.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "terraformazurenginx-nic-assoc" {
  network_interface_id      = azurerm_network_interface.terraformazurenginx-networkinterface.id
  network_security_group_id = azurerm_network_security_group.terraformazurenginx-ng.id
}

resource "tls_private_key" "nginx-private-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.nginx-private-key.private_key_pem
  filename        = "key.pem"
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "nginx-vm" {
  name                = "nginx-vm"
  resource_group_name = azurerm_resource_group.terraformazurenginx.name
  location            = azurerm_resource_group.terraformazurenginx.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.terraformazurenginx-networkinterface.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.nginx-private-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  depends_on = [
    local_file.private_key
  ]
}

data "azurerm_public_ip" "data-public-ip" {
  name = azurerm_public_ip.publicip.name
  resource_group_name = azurerm_resource_group.terraformazurenginx.name
}

resource "null_resource" "installing-nginx" {
  triggers = {
    order = azurerm_linux_virtual_machine.nginx-vm.id
  }

  connection {
    type = "ssh"
    host = data.azurerm_public_ip.data-public-ip.ip_address
    user = "adminuser"
    private_key = tls_private_key.nginx-private-key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt -y upgrade",
      "sudo apt install -y nginx"
    ]
  }
  
  depends_on = [
    azurerm_linux_virtual_machine.nginx-vm
  ]
}