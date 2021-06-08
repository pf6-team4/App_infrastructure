terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
       version = "=2.46.0"
    }
  }
  #for remote
  backend "remote" {
    organization = "pleianthos"
    workspaces {
      name = "application"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_appId
  client_secret   = var.client_password
  tenant_id       = var.tenant_id
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-TM4"
  location = var.location
  tags     = var.tags
}

# Create virtual network
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}TFVnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create subnet in the existing virtual network
resource "azurerm_subnet" "main" {
  name                 = "${var.prefix}TFSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes       = ["10.0.1.0/24"]
}

# Create public IP
resource "azurerm_public_ip" "main" {
  name                = "${var.prefix}TFPublicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  tags                = var.tags
}

# Create Network Security Group and rule
# Network Security Groups control the flow of network traffic in and out of your VM.
resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}TFNSG"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "SSH"
    priority                   = 1001
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
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

# Create network interface
# A virtual network interface card (NIC) connects your VM to a given virtual network, 
# public IP address, and network security group. 
resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}NIC"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "${var.prefix}NICConfg"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "main" {
    network_interface_id      = azurerm_network_interface.main.id
    network_security_group_id = azurerm_network_security_group.main.id
}


# Create an SSH key
resource "tls_private_key" "main_ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
 
}


# Create a Linux virtual machine and instal jenkins, maven and Ansible in the VM
resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${var.prefix}TFVM"
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.main.id]
  size                  = "Standard_DS1_v2"
  tags                  = var.tags

  os_disk {
    name                 = "${var.prefix}OsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = lookup(var.sku, var.location)
    version   = "latest"
  }

  computer_name  = "${var.prefix}TFVM"
  admin_username = var.admin_username
  disable_password_authentication = true
  
  
  admin_ssh_key {
        username = var.admin_username
         public_key = tls_private_key.main_ssh.public_key_openssh
  }

  

  provisioner "remote-exec" { 
  inline=[
          "sudo su <<EOF",
          "sudo apt-get -q update",
          "sudo apt install -y default-jdk",
          "sudo apt-get install -y maven",
          "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common",
          "sudo apt install -y curl",
          "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
          "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'",
          "sudo apt-get -q update",
          "apt-cache policy docker-ce",
          "sudo apt install -y docker-ce",
  ]
  on_failure = continue

    connection {
                  type        = "ssh"
                  user        = var.admin_username
                  private_key = tls_private_key.main_ssh.private_key_pem
                  host        = azurerm_public_ip.main.ip_address
    }
  }



}

#data source
data "azurerm_public_ip" "main" {
  name                = azurerm_public_ip.main.name
  resource_group_name = azurerm_linux_virtual_machine.main.resource_group_name
  depends_on          = [azurerm_linux_virtual_machine.main]
}

