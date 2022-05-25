"use strict";

// A bare-bones CSV parser for the new mass user import/update tool.
// Executed in a Web Worker thread.

// Splits a string into tokens, separated by single-character separators. Understands escaped
// separators and ignores separators that appear inside quoted strings.
function _splitString(string, separator)
{
    let pos = 0,
        tokens = [],
        quote = 0,
        foundQuotes = false,
        currToken = "",
        prevChar = null;

    while (pos < string.length) {
        const c = string[pos];

        switch (c) {
            // Quote on/off
            case '"':
                quote = !quote;
                foundQuotes = true;
                break;

            // Split, unless quoted or escaped
            case separator:
                if (quote || prevChar == "\\")
                    currToken += c;
                else {
                    tokens.push(currToken);
                    currToken = "";
                    foundQuotes = false;
                }

                break;

            // Pass escapes through as-is
            case "\\":
                if (prevChar == "\\")
                    currToken += c;

                break;

            // Accumulate token
            default:
                currToken += c;
                break;
        }

        prevChar = c;
        pos++;
    }

    // Final token?
    if (currToken.length > 0 || foundQuotes)
        tokens.push(currToken);

    return tokens;
}

// The core CSV parser
function _parseCSV(source, settings)
{
    try {
        const t0 = performance.now();

        // Ensure we nave nice and clean Unicode data
        source = source.normalize("NFC");

        // Remove Window-style newlines
        source = source.replace(/\r\n/g, "\n");

        // Remove Unicode BiDi mess no one wants to deal with
        source = source
            .replace(/\u200E/g, '')     // U+200E LEFT-TO-RIGHT MARK (LRM)
            .replace(/\u200F/g, '')     // U+200F RIGHT-TO-LEFT MARK (RLM)
            .replace(/\u202A/g, '')     // U+202A LEFT-TO-RIGHT EMBEDDING (LRE)
            .replace(/\u202B/g, '')     // U+202B RIGHT-TO-LEFT EMBEDDING (RLE)
            .replace(/\u202C/g, '')     // U+202C POP DIRECTIONAL FORMATTING (PDF)
            .replace(/\u202D/g, '')     // U+202D LEFT-TO-RIGHT OVERRIDE (LRO)
            .replace(/\u202E/g, '')     // U+202E RIGHT-TO-LEFT OVERRIDE (RLO)
            .replace(/\u2066/g, '')     // U+2066 LEFT-TO-RIGHT ISOLATE (LRI)
            .replace(/\u2067/g, '')     // U+2067 RIGHT-TO-LEFT ISOLATE (RLI)
            .replace(/\u2068/g, '')     // U+2068 FIRST STRONG ISOLATE (FSI)
            .replace(/\u2069/g, '')     // U+2069 POP DIRECTIONAL ISOLATE (PDI)
            .replace(/\u061C/g, '')     // U+061C ARABIC LETTER MARK (ALM)
        ;

        let lineNumber = 0,
            rows = [];

        let minColumns = 99999999,
            maxColumns = 0;

        let headers = null;

        // Split into rows and then split every row
        for (const row of source.split("\n")) {
            lineNumber++;

            if (row.length == 0)
                continue;

            let saveHeader = false;

            let parts = _splitString(row, settings.separator);

            if (settings.trimValues)
                parts = parts.map((str) => str.trim());

            if (settings.wantHeader && lineNumber == 1) {
                // Store header parts separately
                headers = [...parts];

                // If the first row starts with a #, remove it as it usually means
                // it's a comment
                if (headers[0][0] == "#") {
                    headers[0] = headers[0].substring(1);
                    console.log("[parser] Autoremoved the first row comment marker");
                }

                continue;
            }

            minColumns = Math.min(minColumns, parts.length);
            maxColumns = Math.max(maxColumns, parts.length);

            rows.push({
                state: 0,           // internal state flags
                row: lineNumber,
                columns: parts,
            });
        }

        const t1 = performance.now();

        console.log(`[parser] _parseCSV(): parsing took ${t1 - t0} ms`);

        return {
            state: "ok",
            message: null,
            headers: headers,
            rows: rows,
        };
    } catch (e) {
        console.error(e);

        return {
            state: "error",
            message: e.toString(),
            headers: null,
            rows: null,
        };
    }
}

// Worker Thread interface
onmessage = function(e)
{
    postMessage(_parseCSV(e.data.source, e.data.settings));
};
