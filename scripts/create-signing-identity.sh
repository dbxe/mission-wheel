#!/bin/zsh
set -euo pipefail

identity_name="Mission Wheel Signing"
login_keychain="${HOME}/Library/Keychains/login.keychain-db"
openssl_bin="/usr/bin/openssl"

identity_exists() {
  security find-identity -v -p codesigning 2>/dev/null | awk -F '"' -v name="${identity_name}" '$2 == name { found = 1 } END { exit found ? 0 : 1 }'
}

if identity_exists; then
  echo "Code signing identity already exists: ${identity_name}"
  exit 0
fi

if [[ ! -f "${login_keychain}" ]]; then
  echo "Login keychain not found: ${login_keychain}" >&2
  exit 1
fi

echo "Creating code signing identity: ${identity_name}"
echo "macOS may show one-time keychain or trust prompts. On first signing, codesign may ask for keychain access; choose Always Allow."

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

key_path="${work_dir}/key.pem"
cert_path="${work_dir}/cert.pem"
p12_path="${work_dir}/identity.p12"
openssl_config_path="${work_dir}/openssl.cnf"
p12_password="$("${openssl_bin}" rand -base64 48)"

cat > "${openssl_config_path}" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_codesign
prompt = no

[ dn ]
CN = ${identity_name}

[ v3_codesign ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

# Pin the system LibreSSL and legacy PKCS#12 algorithms: OpenSSL 3.x defaults
# (AES + SHA-256 MAC) produce bundles that `security import` cannot read.
"${openssl_bin}" req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "${key_path}" \
  -x509 \
  -days 3650 \
  -out "${cert_path}" \
  -config "${openssl_config_path}" \
  -sha256 >/dev/null

"${openssl_bin}" pkcs12 \
  -export \
  -inkey "${key_path}" \
  -in "${cert_path}" \
  -name "${identity_name}" \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -out "${p12_path}" \
  -passout "pass:${p12_password}" >/dev/null

security import "${p12_path}" \
  -k "${login_keychain}" \
  -P "${p12_password}" \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "${login_keychain}" \
  "${cert_path}" >/dev/null

if ! identity_exists; then
  echo "Created certificate, but security does not list it as a usable code signing identity." >&2
  exit 1
fi

echo "Created code signing identity: ${identity_name}"
