#!/bin/bash
# Run every c7btlb test, print the result of each and a summary.
# Exit status is 1 if any test fails.
#
#   test0                    original unit tests
#   test1_multihit_priority  several matching entries, lowest index (enc4)
#   test2_invtlb             INVTLB ops, reset, E=0 writes
#   test3_search_port        search timing and match rules
#   test4_random             random operations against a reference model
#   test5_page_size          PS=22 (4 MB) entries, not supported yet

TESTS="test0 test1_multihit_priority test2_invtlb test3_search_port test4_random"

echo run tests
echo

pass=0
fail=0
failed=""

for t in $TESTS; do
    echo "$t"
    result=$(cd "$t" && ./simulate.sh)
    if echo "$result" | grep -q "FAIL"; then
        echo "$result" | grep -E "FAIL|TEST SUMMARY" | head -10
        printf "FAIL!\n"
        fail=$((fail + 1))
        failed="$failed $t"
    elif echo "$result" | grep -q "PASS"; then
        printf "PASS!\n"
        pass=$((pass + 1))
    else
        printf "Unknown result\n"
        fail=$((fail + 1))
        failed="$failed $t"
    fi
    echo ""
done

echo "$pass passed, $fail failed"
if [ $fail -ne 0 ]; then
    echo "failed:$failed"
    exit 1
fi
