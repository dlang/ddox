var fs = require('fs'),
    phantomcss = require(fs.workingDirectory + '/node_modules/phantomcss/phantomcss.js');

casper.test.begin('ddox visual test', function(test) {
    phantomcss.init({
        libraryRoot: './node_modules/phantomcss',
        screenshotRoot: './test/screenshots',
        failedComparisonsRoot: './test/failures',
        addLabelToFailedImage: false
    });

    casper
        .start('http://localhost:8080/vibe.web.rest/registerRestInterface')
        .viewport(1024, 768)
        .then(function() {
            phantomcss.screenshot('#main-contents > section:nth-child(3)', 'declaration_prototype');
        })
        .then(function() {
            phantomcss.screenshot('#main-contents > section:nth-child(5)', 'function_parameters');
        })
        .then(function() {
            phantomcss.screenshot('#main-contents > section:nth-child(7)', 'code_example');
        });

    casper
        .then(function() {
            phantomcss.compareAll();
        })
        .run(function() {
            test.done();
        });
});
