#!/bin/bash
echo run tests
echo


cd test0
echo "test0"
result=$(./simulate.sh)
if echo "$result" | grep "FAIL"; then
    printf "FAIL!\n"
    exit 1
elif echo "$result" | grep "PASS"; then
    printf "PASS!\n"
else
    printf "Unknown result\n"
    exit 1
fi
echo ""
cd ..


