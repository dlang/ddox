#!/usr/bin/env bash

set -ueo pipefail

dub test --compiler=${DC:=dmd}
dub build --compiler=${DC}

failure=0
shopt -s globstar # for **/*.d expansion
for dir in tests/*; do
    pushd $dir
    ${DMD:-dmd} -Xftest.json -Df__dummy.html -c -o- **/*.d
    if [ -f .filter_args ]; then
        filter_args=$(cat .filter_args)
    fi
    ../../ddox filter ${filter_args:-} test.json
    if [ -f .gen_args ]; then
        gen_args=$(cat .gen_args)
    fi
    ../../ddox generate-html --html-style=pretty ${gen_args:-} test.json docs
    if [ ! -f .no_diff ] && ! git --no-pager diff --exit-code -- docs; then
        failure=1
    fi
    popd
done
shopt -u globstar

./ddox serve-html test/test.json &
PID=$!
cleanup() { kill $PID; }
trap cleanup EXIT

# Don't run the phantomcss-tester on the Project Tester (no docker available)
if [ "${DETERMINISTIC_HINT:-0}" -eq 1 ] ; then
    exit 0
fi

bridgeip=$(ip -4 addr show dev docker0 | sed -n 's|.*inet \(.*\)/.*|\1|p')
if ! docker run --rm --env LISTEN_ADDR="http://$bridgeip:8080" \
     --volume=$PWD/test:/usr/src/app/test martinnowak/phantomcss-tester test test/test.js; then
    # upload failing screenshots
    cd test/screenshots
    for img in *.{diff,fail}.png; do
        ARGS="${ARGS:-} -F name=@$img"
    done
    curl -fsSL https://img.vim-cn.com/ ${ARGS:-}
    failure=1
fi

exit $failure
