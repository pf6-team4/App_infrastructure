output "os_sku" {
  value = lookup(var.sku, var.location)
}

output "public_ip_address" {
  value = data.azurerm_public_ip.main.ip_address
}

output "tls_private_key" { 
    value = tls_private_key.main_ssh.private_key_pem 
    sensitive = true
}