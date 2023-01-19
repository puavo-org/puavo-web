import { pad } from "../../common/utils.js";

// Scaler for converting between JavaScript dates and unixtimes
const JAVASCRIPT_TIME_GRANULARITY = 1000;

export function convertTimestamp(unixtime, dateOnly = false)
{
    if (unixtime < 0)
        return "";

    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return [false, "(INVALID)"];

    try {
        // I'm not sure what kind of errors this can throw and when
        const d = new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY);

        // Why is there no sprintf() in JavaScript?
        if (dateOnly) {
            return [
                true,
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`];
        } else {
            return [
                true,
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
            ];
        }
    } catch (e) {
        console.log(e);
        return [false, "(ERROR)"];
    }
}
