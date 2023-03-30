"use strict";

// Web Worker Thread for SuperTable mass operations

// Almost a verbatim copy of the users import/update tool's worker thread.
// I think these files could be shared, but it would require some large-scale
// reworking I'm not too keen to do right now.

// How many times we'll retry a batch before giving up and halting the process
const MAX_ATTEMPTS = 3;

function sleep(ms)
{
    return new Promise(resolve => setTimeout(resolve, ms));
}

let attempt = 0;

// Send one batch of data to the server and interprets the return value.
// Thank $(deity) async functions can be called from onmessage below.
async function _processBatch(url, csrf, singleShot, operation, parameters, rows)
{
    while (true) {
        console.log(`[worker] Network request attempt ${attempt}`);

        let response = null;
        let hardFail = false;

        await fetch(url, {
            method: "POST",
            mode: "cors",
            headers: {
                // Use text/plain because if it's "application/json" RoR happily logs all the
                // parameters in plaintext, including passwords (logging sanitization does not
                // work because the parameters aren't named)
                "Content-Type": "text/plain; charset=utf-8",
                "X-CSRF-Token": csrf,
            },
            body: JSON.stringify({
                operation: operation,
                singleShot: singleShot,
                parameters: parameters,
                rows: rows,
            })
        }).then(response => {
            if (!response.ok)
                throw response;

            return response.text();
        }).then(data => {
            response = JSON.parse(data);
        }).catch(error => {
            console.error(error);

            if (error.status == 500) {
                // 500 errors halt the process immediately
                hardFail = true;
                postMessage({ message: "server_error", error: error.status });
                return;
            }
        });

        if (hardFail) {
            console.error("[worker] hardFail is true, bailing out");
            return;
        }

        if (response) {
            if (response.ok) {
                postMessage({
                    message: "batch_processed",
                    result: response.rows
                });

                return;
            }

            console.error(response);

            postMessage({
                message: "server_error",
                error: response.message + "\n\nrequest_id: " + response.request_id
            });

            return;
        }

        // Retry, if possible
        if (attempt < MAX_ATTEMPTS) {
            console.error("[worker] Trying again in 1 second...");
            attempt++;

            await sleep(1000);
        } else {
            console.error("[worker] All attempts used, giving up");

            postMessage({
                message: "network_error",
                error: "Network error?"
            });

            return;
        }
    }
}

async function _skipBatch()
{
    await sleep(500);

    postMessage({
        message: "batch_skipped"
    });
}

onmessage = function(e)
{
    switch (e.data.message) {
        case "skip_batch":
            _skipBatch();
            break;

        case "process_batch":
            attempt = 1;
            _processBatch(e.data.url, e.data.csrf, e.data.singleShot, e.data.operation, e.data.parameters, e.data.rows);
            break;

        default:
            console.error(`[worker] Received an unknown message "${e.data.message}"`);
            break;
    }
};
