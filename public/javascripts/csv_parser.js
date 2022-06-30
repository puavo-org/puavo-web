"use strict";

// A bare-bones CSV parser for the new mass user import/update tool.
// Executed in a Web Worker thread.

// How many rows the preview mode displays
const PREVIEW_ROWS = 5;

// Splits a string into tokens, separated by single-character separators. Understands escaped
// separators and ignores separators that appear inside quoted strings.
function _splitString(string, separator)
{
    let pos = 0,
        tokens = [],
        currToken = "",
        quote = false;

    while (pos < string.length) {
        const c = string[pos];

        if (c == "\\") {
            // Escape
            if (pos + 1 < string.length) {
                const next = string[pos + 1];

                switch (next) {
                    case "t":
                    case "n":
                    case "v":
                    case "b":
                        // Eat Tabs and newlines. Usernames, etc. cannot contain hard tabs
                        // or newlines.
                        break;

                    default:
                        currToken += next;
                        break;
                }

                // Skip the escaped character
                pos++;
            } else break;
        } else if (c == "\"") {
            // Quoting start/end, don't store the quote character
            quote = !quote;
        } else if (c == separator && !quote) {
            // Split
            tokens.push(currToken);
            currToken = "";
        } else currToken += c;

        pos++;
    }

    if (currToken.length > 0)
        tokens.push(currToken);

    return tokens;
}

// The core CSV parser
function _parseCSV(source, settings, isPreview)
{
    if (source === null || source === undefined) {
        console.log("[parser] _parseCSV(): the source data is completely empty");

        return {
            state: "ok",
            message: null,
            isPreview: isPreview,
            headers: [],
            rows: [],
        };
    }

    try {
        const t0 = performance.now();

        // Ensure we nave nice and clean Unicode data
        source = source.normalize("NFC");

        // Remove Windows-style newlines
        source = source.replace(/\r\n/g, "\n");

        // Remove Unicode BiDi mess no one wants to deal with. Puavo doesn't support
        // right-to-left content anyway.
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

        const maxLines = isPreview ? (settings.wantHeader ? PREVIEW_ROWS + 1 : PREVIEW_ROWS) : 9999999;

        // Split into rows and then split every row
        for (const row of source.split("\n")) {
            lineNumber++;

            if (lineNumber > maxLines)
                break;

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
                row: lineNumber,
                columns: parts,
                state: 0,           // internal table state flags
            });
        }

        const t1 = performance.now();

        console.log(`[parser] _parseCSV(): parsing took ${t1 - t0} ms`);

        return {
            state: "ok",
            message: null,
            isPreview: isPreview,
            headers: headers,
            rows: rows,
        };
    } catch (e) {
        console.error(e);

        return {
            state: "error",
            message: e.toString(),
            isPreview: isPreview,
            headers: null,
            rows: null,
        };
    }
}

// Worker Thread interface
onmessage = function(e)
{
    postMessage(_parseCSV(e.data.source, e.data.settings, e.data.isPreview));
};
