#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate named
# "NotchIsland Local" in your login keychain.
#
# Why: run-app.sh otherwise signs every build with a new throwaway (ad-hoc)
# signature, so macOS treats each rebuild as a different app and asks again for
# Screen Recording, Calendar, Location and Automation. With this certificate every
# build has the same identity and macOS remembers what you allowed.
#
# The certificate and its private key stay in your login keychain and are only
# trusted for code signing by your user account. macOS asks for your password once
# to trust it. To remove it later, delete "NotchIsland Local" in Keychain Access.
set -euo pipefail

NAME="NotchIsland Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS's own LibreSSL writes a .p12 that the keychain can import.
OPENSSL=/usr/bin/openssl

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" is already set up."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

echo "==> Creating certificate"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -name "$NAME" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:notchisland

echo "==> Adding it to your login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P notchisland -T /usr/bin/codesign

echo "==> Trusting it for code signing (macOS asks for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Done. Rebuild with ./scripts/run-app.sh."
  echo "macOS will ask for each permission one more time, then remember it."
else
  echo "The certificate was added but isn't usable for signing yet." >&2
  echo "Open Keychain Access, find \"$NAME\", and set Trust > Code Signing to Always Trust." >&2
  exit 1
fi
