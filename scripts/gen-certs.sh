#!/usr/bin/env bash
# Génère une autorité de certification locale (CA) et un certificat *.cr465.test
# signé par elle. Les fichiers restent sur la VM (ignorés par Git).
# Utilisation (depuis la racine du dépôt) :  bash scripts/gen-certs.sh
set -euo pipefail

DOMAIN="${1:-cr465.test}"
DIR="$(cd "$(dirname "$0")/.." && pwd)/compose/traefik/certs"
mkdir -p "$DIR"
cd "$DIR"

# 1. Autorité de certification locale (créée une seule fois)
if [ ! -f ca.key ]; then
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -key ca.key -sha256 -days 825 \
    -subj "/CN=CR465 Local CA/O=CR465" -out ca.crt
  echo "CA locale creee : $DIR/ca.crt"
fi

# 2. Certificat serveur générique pour tous les sous-domaines
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$DOMAIN.key" -subj "/CN=*.$DOMAIN" -out "$DOMAIN.csr"

cat > ext.cnf <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN
EOF

openssl x509 -req -in "$DOMAIN.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out "$DOMAIN.crt" -days 397 -sha256 -extfile ext.cnf

rm -f "$DOMAIN.csr" ext.cnf
chmod 600 ./*.key
chmod 644 ./*.crt
echo "Certificat cree : $DIR/$DOMAIN.crt (valide pour $DOMAIN et *.$DOMAIN)"
