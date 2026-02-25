import { pad } from "../../common/utils.js";

// Scaler for converting between JavaScript dates and unixtimes
export const JAVASCRIPT_TIME_GRANULARITY = 1000;

export function convertTimestamp(unixtime, dateOnly = false, formatter = null)
{
    if (unixtime < 0)
        return "";

    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return [false, "(INVALID)", null];

    try {
        // I'm not sure what kind of errors this can throw and when
        const d = new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY);

        if (formatter) {
            // Use the supplied formatter function instead
            const hover = dateOnly ?
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` :
                d.toISOString();

            // Omit the "timestamp" class from the abbr element to prevent the on-page JavaScript from attempting
            // to localize. It would fail anyway, as the contents of the abbr element isn't an ISO 8601 string.
            return [true, `<abbr title="${hover}">${formatter.format(d)}</abbr>`, d];
        }

        // Why is there no sprintf() in JavaScript?
        if (dateOnly) {
            return [
                true,
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
                d];
        } else {
            return [
                true,
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`,
                d
            ];
        }
    } catch (e) {
        console.log(e);
        return [false, "(ERROR)", null];
    }
}

// Type checking stuff
export const isNullOrUndefined = i => i === null || i === undefined;
export const isObject = i => !isNullOrUndefined(i) && typeof(i) === 'object';
