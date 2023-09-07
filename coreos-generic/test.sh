#/bin/bash
#set -x
source luks-helpers.sh
fatal() {
    echo "FATAL: $@"
    exit 1
}
test_parseClevisRegex() {
    local expected=$1
    #shift
    output=$(parseClevisRegex "$4" $2 $3)
    echo $output

    [[ "$output" == "$expected" ]] || fatal "within failed: Expected rc $expected != $output"
}

read -r -d '' EXPECTED_OUTPUT <<EOM
1|/dev/sda4|1|1,7|{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}
1|/dev/sda4|2|1,7|{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}
EOM

read -r -d '' INPUT <<EOM
1: tpm2 '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}'
2: tpm2 '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}'
EOM

test_parseClevisRegex "$EXPECTED_OUTPUT" "1" "/dev/sda4" "$INPUT"
