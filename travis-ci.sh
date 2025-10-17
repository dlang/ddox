#!/usr/bin/env bash

set -xueo pipefail

if [[ ${DC:-} == "" ]]; then
    if [[ ${COMPILER:-} == *"ldc"* ]]; then DC=ldc2; DMD=ldmd2
    elif [[ ${COMPILER:-} == *"gdc"* ]]; then DC=gdc; DMD=gdmd
    else DC=dmd; DMD=dmd
    fi
fi

dub test --compiler=${DC}
dub build --compiler=${DC}

failure=0
shopt -s globstar # for **/*.d expansion
for dir in tests/*; do
    pushd $dir
    ${DMD:-dmd} -Xftest.json -Dd__dummy_html -c -o- **/*.d
    if [ -f .filter_args ]; then
        filter_args=$(cat .filter_args)
    fi
    ../../ddox filter ${filter_args:-} test.json
    if [ -f .gen_args ]; then
        gen_args=$(cat .gen_args)
    fi
    ../../ddox generate-html --html-style=pretty ${gen_args:-} test.json docs
    if [ ! -f .no_diff ] && ! git --no-pager diff --exit-code -- docs; then
        echo "FAILED: HTML generation test failed: $dir"
        failure=1
    fi
    popd
done
shopt -u globstar

# test for changes breaking the vibed.org build
rm -rf vibed.org
git clone https://github.com/vibe-d/vibed.org.git
dparsever=`sed ':a;N;$!ba; s/.*\"libdparse\":\ \"\([^\"]*\)\",.*/\1/' dub.selections.json`
sed -i 's/\"libdparse\":\ \".*",/\"libdparse\":\ \"$(dparsever)\",/' vibed.org/dub.selections.json
sed -i 's/\"ddox\":\ \".*",/\"ddox\":\ {\"path\":\"..\"},/' vibed.org/dub.selections.json
if ! dub build --root vibed.org; then
    echo "FAILED: vibed.org produced build errors"
    failure=1
fi

# Don't run the phantomcss-tester on the Project Tester (no docker available)
if [ "${DETERMINISTIC_HINT:-0}" -eq 1 ] ; then
    exit $failure
fi

./ddox serve-html test/test.json &
PID=$!
cleanup() { kill $PID; }
trap cleanup EXIT

bridgeip=$(ip -4 addr show dev docker0 | sed -n 's|.*inet \(.*\)/.*|\1|p')
if ! docker run --rm --env LISTEN_ADDR="http://$bridgeip:8080" \
     --volume=$PWD/test:/usr/src/app/test martinnowak/phantomcss-tester test test/test.js; then
    echo "FAILED: PhantomCSS test failed"
    failure=1
fi

exit $failure
