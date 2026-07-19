#!/usr/bin/env bash
# Generates a self-signed CA and a MinIO server certificate signed by it using OpenSSL.
# MinIO auto-loads certs/private.key + certs/public.crt for TLS (HTTPS on :9000/:9001).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

DAYS=825
SUBJ_CA="/C=KE/ST=Nairobi/L=Nairobi/O=DSA4030-Group4/OU=SecurityConsulting/CN=DSA4030-Group4-RootCA"
SUBJ_SERVER="/C=KE/ST=Nairobi/L=Nairobi/O=DSA4030-Group4/OU=SecureCloudStorage/CN=minio"

echo "[*] Generating root CA key + certificate..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$DAYS" \
  -subj "$SUBJ_CA" -out ca.crt

echo "[*] Generating MinIO server key + CSR..."
openssl genrsa -out private.key 2048
openssl req -new -key private.key -subj "$SUBJ_SERVER" -out minio.csr

echo "[*] Signing server certificate with root CA (SANs: localhost, minio, 127.0.0.1)..."
cat > san.ext <<EOF
subjectAltName = DNS:localhost,DNS:minio,DNS:audit-webhook,IP:127.0.0.1
extendedKeyUsage = serverAuth
EOF

openssl x509 -req -in minio.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out public.crt -days "$DAYS" -sha256 -extfile san.ext

rm -f minio.csr san.ext ca.srl
chmod 600 private.key ca.key

echo "[+] Done. Files in $CERT_DIR:"
ls -la "$CERT_DIR"
echo
echo "public.crt / private.key -> used by MinIO for TLS"
echo "ca.crt                   -> trust this CA when using 'mc' or curl against https://localhost:9000"
