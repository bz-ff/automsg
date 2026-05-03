#!/bin/bash
# One-time setup: create a stable self-signed code-signing identity so AutoMsg
# rebuilds keep their Full Disk Access / Contacts / Local Network grants.
#
# WHY: macOS TCC keys grants on the app's code-signing identity hash. Ad-hoc
# signing produces a new hash every build, so each rebuild looks like a brand
# new app and macOS forgets the grants. A stable self-signed identity solves it.
#
# This script is non-interactive — it creates the cert, imports it, and trusts
# it for code signing in the login keychain. No sudo or GUI required.
set -e

CERT_NAME="AutoMsg Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    echo "Identity '$CERT_NAME' already exists. Nothing to do."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code-signing identity: $CERT_NAME"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/cert.cfg" <<'EOF'
[ req ]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ca

[ req_dn ]
CN = AutoMsg Self-Signed

[ v3_ca ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 1. Generate self-signed cert + private key (10-year validity)
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" \
    -days 3650 -config "$TMPDIR/cert.cfg" 2>/dev/null

# 2. Bundle as PKCS#12 (legacy format for consistent macOS handling)
P12_PASS="automsg-$$"
openssl pkcs12 -export -legacy \
    -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -name "$CERT_NAME" \
    -passout pass:"$P12_PASS" 2>/dev/null

# 3. Import into login keychain, allowing codesign to use the key non-interactively
security import "$TMPDIR/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security -A

# 4. Add trust settings to the LOGIN keychain (no sudo required)
#    -p codeSign means "trust this cert for code signing only"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMPDIR/cert.pem"

# Verify
if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    echo ""
    echo "✓ Identity '$CERT_NAME' is now available."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    echo "Future builds will automatically sign with this identity. After your"
    echo "next rebuild, you'll need to grant Full Disk Access ONE more time"
    echo "(because the new signature differs from previous ad-hoc ones). After"
    echo "that, all subsequent rebuilds will inherit the grant."
else
    echo "⚠ Cert imported but not visible as a codesigning identity yet."
    echo "  Try running this script again, or check Keychain Access manually."
    exit 1
fi
