#!/usr/bin/env bash

set -ueo pipefail

dub test --compiler=${DC:=dmd}
dub build --compiler=${DC}

failure=0
shopt -s globstar # for **/*.d expansion
for dir in tests/*; do
    pushd $dir
    ${DMD:-dmd} -Xftest.json -Df__dummy.html -c -o- **/*.d
    ../../ddox generate-html --html-style=pretty test.json docs
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

wget https://github.com/Medium/phantomjs/releases/download/v2.1.1/phantomjs-2.1.1-linux-x86_64.tar.bz2
tar -C $HOME -jxf phantomjs-2.1.1-linux-x86_64.tar.bz2
export PATH="$HOME/phantomjs-2.1.1-linux-x86_64/bin/:$PATH"

npm install phantomcss -q
if ! ./node_modules/phantomcss/node_modules/.bin/casperjs test test/test.js ; then
    # upload failing screenshots
    cd test/screenshots
    for img in *.{diff,fail}.png; do
        ARGS="${ARGS:-} -F name=@$img"
    done
    curl -fsSL https://img.vim-cn.com/ ${ARGS:-}
    failure=1
fi

exit $failure
