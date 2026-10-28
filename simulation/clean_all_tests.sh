#!/bin/bash
echo clean tests
echo

TESTS="test0 test1_multihit_priority test2_invtlb test3_search_port test4_random test5_page_size"

for t in $TESTS; do
    echo "$t"
    (cd "$t" && ./clean.sh)
    echo ""
done
