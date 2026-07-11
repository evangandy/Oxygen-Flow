#!/bin/bash
# Create a self-signed code signing certificate for FlowLocal development.
# This gives the app a stable identity so macOS doesn't revoke Accessibility
# permissions on every rebuild.
set -euo pipefail

CERT_NAME="FlowLocal Dev"
KEYCHAIN="login.keychain-db"

echo "==> Creating self-signed code-signing certificate: '$CERT_NAME'"

# Create a certificate signing request config
cat > /tmp/flowlocal_cert.conf << 'EOF'
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = FlowLocal Dev
O  = FlowLocal
[ codesign ]
keyUsage         = digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate key + self-signed cert
openssl req -x509 -newkey rsa:2048 -keyout /tmp/flowlocal_key.pem \
  -out /tmp/flowlocal_cert.pem -days 3650 -nodes \
  -config /tmp/flowlocal_cert.conf -extensions codesign 2>/dev/null

# Bundle into PKCS12
openssl pkcs12 -export -out /tmp/flowlocal.p12 \
  -inkey /tmp/flowlocal_key.pem -in /tmp/flowlocal_cert.pem \
  -passout pass:flowlocal 2>/dev/null

# Import into login keychain and trust for code signing
security import /tmp/flowlocal.p12 -k "$KEYCHAIN" -P flowlocal \
  -T /usr/bin/codesign -T /usr/bin/security

# Set the certificate as trusted for code signing
security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" /tmp/flowlocal_cert.pem

# Allow codesign to access the key without prompting
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" 2>/dev/null || true

# Cleanup temp files
rm -f /tmp/flowlocal_key.pem /tmp/flowlocal_cert.pem /tmp/flowlocal.p12 /tmp/flowlocal_cert.conf

echo "==> Done! Verifying..."
security find-identity -v -p codesigning | grep "FlowLocal Dev"
echo "==> Certificate '$CERT_NAME' is ready for code signing."
