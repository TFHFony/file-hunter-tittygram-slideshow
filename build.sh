#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1

python3 tools/makeadf.py
status=$?
echo

if [ $status -eq 0 ]
then
    echo "Build OK: out/slideshow.adf"
else
    echo "BUILD FAILED"
    exit 1
fi

echo
