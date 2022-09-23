"use strict";

// Sends the import table rows to the server in batches, then interprets the results

// How many times we'll retry a batch before giving up and halting the process
const MAX_ATTEMPTS = 3;

function sleep(ms)
{
    return new Promise(resolve => setTimeout(resolve, ms));
}

let data = null;

let start = 0,
    total = 0,
    attempt = 1;

function _beginImport(incoming)
{
    data = {...incoming};
    start = incoming.startIndex;    // the process can be resumed from arbitrary point
    total = 0;
    attempt = 1;
}

// Send one batch of data to the server and interprets the return value.
// Thank $(deity) async functions can be called from onmessage below.
async function _importNextBatch()
{
    console.log(`[worker] start=${start} total=${total} len=${data.rows.length - 1}`);

    if (!data || start > data.rows.length - 1) {
        // All done
        console.log("[worker] All data has been processed");
        postMessage({ message: "complete" });
        return;
    }

    // Process the rows in batches, so not every row causes its own HTTP request
    // and a database authentication and who knows what else
    const rows = data.rows.slice(start, start + data.batchSize);

    while (true) {
        console.log(`[worker] Rows ${start} -> ${start + rows.length - 1}, attempt ${attempt}`);

        let response = null;

        let hardFail = false;

        await fetch(`/users/${data.school}/new_import/import`, {
            method: "POST",
            mode: "cors",
            headers: {
                // Use text/plain because if it's "application/json" RoR happily logs all the
                // parameters in plaintext, including passwords (logging sanitization does not
                // work because the parameters aren't named)
                "Content-Type": "text/plain; charset=utf-8",
                "X-CSRF-Token": data.csrf,
            },
            body: JSON.stringify({
                columns: data.headers,
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
                start += data.batchSize;
                total += rows.length;       // the array wasn't necessarily evenly-sized
                attempt = 1;

                //console.log(response.rows);

                postMessage({ message: "progress", total: total, states: response.rows });
                return;
            }

            console.error(response.error);
        }

        // Retry, if possible
        if (attempt < MAX_ATTEMPTS) {
            console.error("[worker] Trying again in 1 second...");
            attempt++;
            await sleep(1000);
        } else {
            console.error("[worker] All attempts used, giving up");
            postMessage({ message: "server_error", error: "Network error?" });
            return;
        }
    }
}

// Worker Thread interface
onmessage = function(e)
{
    console.log(`[worker] Main thread sent "${e.data.message}"`);

    switch (e.data.message) {
        case "start":
            _beginImport(e.data);
            _importNextBatch();
            break;

        case "continue":
            _importNextBatch();
            break;

        default:
            console.error(`[worker] Received an unknown message "${e.data.message}"`);
            break;
    }
};
