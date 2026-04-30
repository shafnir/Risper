#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Risper Local Development Code Signing"
CODESIGN_DIR="$HOME/Library/Application Support/Risper/CodeSigning"
KEYCHAIN="$CODESIGN_DIR/RisperLocalCodeSigning.keychain-db"
PASSWORD_FILE="$CODESIGN_DIR/keychain-password"

mkdir -p "$CODESIGN_DIR"
chmod 700 "$CODESIGN_DIR"

existing_identity_ready() {
  local password
  local ready=1

  if [[ ! -f "$KEYCHAIN" || ! -r "$PASSWORD_FILE" || ! -s "$PASSWORD_FILE" ]]; then
    return 1
  fi

  password="$(<"$PASSWORD_FILE")"
  cleanup_existing_identity_check() {
    security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  }
  trap cleanup_existing_identity_check EXIT
  trap 'cleanup_existing_identity_check; trap - EXIT HUP INT TERM; exit 129' HUP
  trap 'cleanup_existing_identity_check; trap - EXIT HUP INT TERM; exit 130' INT
  trap 'cleanup_existing_identity_check; trap - EXIT HUP INT TERM; exit 143' TERM

  if ! security unlock-keychain -p "$password" "$KEYCHAIN" >/dev/null 2>&1; then
    cleanup_existing_identity_check
    trap - EXIT HUP INT TERM
    unset -f cleanup_existing_identity_check
    return 1
  fi

  if security find-identity -p codesigning -v "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
    ready=0
  fi

  cleanup_existing_identity_check
  trap - EXIT HUP INT TERM
  unset -f cleanup_existing_identity_check
  return "$ready"
}

if existing_identity_ready; then
  echo "setup_local_codesign: existing identity is ready: $IDENTITY_NAME"
  exit 0
fi

uuidgen | tr '[:upper:]' '[:lower:]' > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

PASSWORD="$(<"$PASSWORD_FILE")"
WORK_DIR="$(mktemp -d /private/tmp/risper-codesign.XXXXXX)"
cleanup() {
  security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT HUP INT TERM; exit 129' HUP
trap 'cleanup; trap - EXIT HUP INT TERM; exit 130' INT
trap 'cleanup; trap - EXIT HUP INT TERM; exit 143' TERM

cat > "$WORK_DIR/openssl.cnf" <<'EOF'
[ req ]
prompt = no
distinguished_name = dn
x509_extensions = codesign

[ dn ]
CN = Risper Local Development Code Signing
O = Risper Local Development

[ codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -keyout "$WORK_DIR/key.pem" \
  -out "$WORK_DIR/cert.pem" \
  -config "$WORK_DIR/openssl.cnf" \
  >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -inkey "$WORK_DIR/key.pem" \
  -in "$WORK_DIR/cert.pem" \
  -out "$WORK_DIR/identity.p12" \
  -passout "pass:$PASSWORD" \
  >/dev/null 2>&1

if [[ -f "$KEYCHAIN" ]]; then
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
fi

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK_DIR/identity.p12" -f pkcs12 -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

security find-identity -p codesigning -v "$KEYCHAIN" | grep -F "$IDENTITY_NAME"
echo "setup_local_codesign: created stable local code-signing identity"
echo "setup_local_codesign: keychain: $KEYCHAIN"
