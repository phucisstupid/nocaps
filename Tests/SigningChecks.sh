#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIGNING_CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nocaps-signing-checks.XXXXXX")"
trap 'rm -rf "$SIGNING_CHECK_DIR"' EXIT
SIGNING_CHECK_IDENTITY="$(openssl x509 -in signing/NoCaps.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
export SIGNING_CHECK_DIR SIGNING_CHECK_IDENTITY
export CI=false
unset NOCAPS_SIGNING_KEYCHAIN
cat > "$SIGNING_CHECK_DIR/security" <<'EOF'
#!/bin/bash
set -euo pipefail
touch "$SIGNING_CHECK_DIR/security-reached"
[[ "$1" == find-identity && "$2" == -p && "$3" == codesigning ]]
if [[ -n "${NOCAPS_SIGNING_KEYCHAIN:-}" ]]; then
    [[ $# == 4 && "$4" == "$NOCAPS_SIGNING_KEYCHAIN" ]]
else
    [[ $# == 3 ]]
fi
case "$SIGNING_CHECK_CASE" in
    missing) printf '0 identities found\n' ;;
    wrong) printf '1) 0000000000000000000000000000000000000000 "Other App"\n' ;;
    error) exit 4 ;;
    matching)
        printf '1) %s "NoCaps Release Signing" (CSSMERR_TP_NOT_TRUSTED)\n' "$SIGNING_CHECK_IDENTITY"
        printf '1 identities found\nValid identities only\n0 valid identities found\n'
        ;;
esac
EOF
cat > "$SIGNING_CHECK_DIR/xcrun" <<'EOF'
#!/bin/bash
touch "$SIGNING_CHECK_DIR/compiler-reached"
exit 73
EOF
chmod +x "$SIGNING_CHECK_DIR/security" "$SIGNING_CHECK_DIR/xcrun"
export PATH="$SIGNING_CHECK_DIR:$PATH"

check_build() {
    local expected="$1" result=0
    shift
    rm -f "$SIGNING_CHECK_DIR/compiler-reached" "$SIGNING_CHECK_DIR/security-reached"
    "$BASH" scripts/build.sh "$@" > "$SIGNING_CHECK_DIR/output" 2>&1 || result=$?
    output="$(cat "$SIGNING_CHECK_DIR/output")"
    if [[ "$result" != "$expected" ]]; then
        printf '%s\n' "$output" >&2
        printf 'Expected exit %s, got %s for %s\n' "$expected" "$result" "$SIGNING_CHECK_CASE" >&2
        exit 1
    fi
}

for SIGNING_CHECK_CASE in missing wrong error; do
    export SIGNING_CHECK_CASE
    check_build 1 --universal --release
    [[ ! -e "$SIGNING_CHECK_DIR/compiler-reached" ]]
    [[ "$output" == *'refusing an ad hoc release'* ]]
done
export SIGNING_CHECK_CASE=matching
check_build 73 --release --universal
[[ -e "$SIGNING_CHECK_DIR/compiler-reached" ]]
[[ "$output" != *'Using ad hoc signing'* ]]
export NOCAPS_SIGNING_KEYCHAIN="$SIGNING_CHECK_DIR/keychain with spaces"
check_build 73 --release
[[ -e "$SIGNING_CHECK_DIR/compiler-reached" ]]
unset NOCAPS_SIGNING_KEYCHAIN
export SIGNING_CHECK_CASE=missing
check_build 73
[[ -e "$SIGNING_CHECK_DIR/compiler-reached" ]]
[[ "$output" == *'Using ad hoc signing for this development build'* ]]
export CI=true SIGNING_CHECK_CASE=matching
check_build 73
[[ -e "$SIGNING_CHECK_DIR/compiler-reached" && ! -e "$SIGNING_CHECK_DIR/security-reached" ]]
[[ "$output" == *'Using ad hoc signing for this development build'* ]]
printf 'Signing safeguards: missing/wrong identities, keychain failures, pinned identity, development fallback, and CI isolation passed\n'
