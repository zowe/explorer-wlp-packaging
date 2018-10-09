#!/bin/sh -e

FUNC=[CreatePax][pre-packaging]
PWD=$(pwd)

# display extracted files
echo "$FUNC content of $PWD...."
find . -print

echo "$FUNC extracting wlp-embeddable-zos-17.0.0.2.pax ..."
cd content
pax -rf ../wlp-embeddable-zos-17.0.0.2.pax -ppx
