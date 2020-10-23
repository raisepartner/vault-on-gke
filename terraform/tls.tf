locals {
    vault_cert = var.manage_tls ? "${tls_locally_signed_cert.vault[0].cert_pem}\n${tls_self_signed_cert.vault-ca[0].cert_pem}" : var.tls_cert
    vault_key = var.manage_tls ? tls_private_key.vault[0].private_key_pem : var.tls_key
    ca_cert    = var.manage_tls ? tls_self_signed_cert.vault-ca[0].cert_pem : var.ca_cert
}

# Generate self-signed TLS certificates. Unlike @kelseyhightower's original
# demo, this does not use cfssl and uses Terraform's internals instead.
resource "tls_private_key" "vault-ca" {
  count = var.manage_tls ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_self_signed_cert" "vault-ca" {
  count = var.manage_tls ? 1 : 0
  key_algorithm   = tls_private_key.vault-ca[0].algorithm
  private_key_pem = tls_private_key.vault-ca[0].private_key_pem

  subject {
    common_name  = "vault-ca.local"
    organization = "HashiCorp Vault"
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "digital_signature",
    "key_encipherment",
  ]

  provisioner "local-exec" {
    command = "echo '${self.cert_pem}' > ../tls/ca.pem && chmod 0600 ../tls/ca.pem"
  }
}

# Create the Vault server certificates
resource "tls_private_key" "vault" {
  count = var.manage_tls ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = "2048"
}

# Create the request to sign the cert with our CA
resource "tls_cert_request" "vault" {
  count = var.manage_tls ? 1 : 0
  key_algorithm   = tls_private_key.vault[0].algorithm
  private_key_pem = tls_private_key.vault[0].private_key_pem

  dns_names = [
    "vault",
    "vault.local",
    "vault.default.svc.cluster.local",
  ]

  ip_addresses = [
    google_compute_address.vault.address,
  ]

  subject {
    common_name  = "vault.local"
    organization = "HashiCorp Vault"
  }
}

# Now sign the cert
resource "tls_locally_signed_cert" "vault" {
  count = var.manage_tls ? 1 : 0
  cert_request_pem = tls_cert_request.vault[0].cert_request_pem

  ca_key_algorithm   = tls_private_key.vault-ca[0].algorithm
  ca_private_key_pem = tls_private_key.vault-ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.vault-ca[0].cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "cert_signing",
    "client_auth",
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  provisioner "local-exec" {
    command = "echo '${self.cert_pem}' > ../tls/vault.pem && echo '${tls_self_signed_cert.vault-ca[0].cert_pem}' >> ../tls/vault.pem && chmod 0600 ../tls/vault.pem"
  }
}
