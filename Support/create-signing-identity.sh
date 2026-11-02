#!/bin/bash
# One-time setup: creates a self-signed code-signing identity in the login keychain.
# Ad-hoc signatures change with every build, so macOS forgets permissions (Accessibility,
# Camera, Reminders) after each rebuild. Signing every build with this identity keeps them.
# The certificate isn't trusted system-wide; delete "NotchApp Local Signing" in Keychain
# Access to remove it.
set -euo pipefail

NAME="NotchApp Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=$(uuidgen)

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null
# -T lets codesign use the key without a keychain prompt on every build.
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\". Run ./build.sh --install."
