/*
These characters have no equivalent in the plain a-z ASCII, so they have to be converted manually,
before the other diacritics are removed. I've seen some of these in production, and without this
table, certain usernames will not be generated correctly.

We only consider lowercase letters because the username has been lowercased by the time we start
removing diacritics from it. "ß" is an exception, because JavaScript's toLowerCase() does not
touch it.
*/
const UNTRANSLATABLE = [
    ['æ', 'ae'],
    ['œ', 'oe'],
    ['ß', 'ss'],
    ['ø', 'o'],
    ['đ', 'd'],
    ['ŀ', 'l'],
    ['ł', 'l'],
];

export function dropDiacritics(string, alternateUmlauts)
{
    let out = string;

    // Convert the "untranslatable" characters first
    for (const [from, to] of UNTRANSLATABLE)
        out = out.replaceAll(from, to)

    if (alternateUmlauts) {
        // Convert some umlauts differently. These conversions won't work in Finnish,
        // but they work in some other languages.
        out = out.replace(/ä/g, "ae");
        out = out.replace(/ö/g, "oe");
        out = out.replace(/ü/g, "ue");
    }

    // Decompose and remove the combining characters (ie. remove everything in the "Combining
    // Diacritical Marks" Unicode block (U+0300 -> U+036F)). This leaves the base characters
    // intact.
    out = out.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

    // Finally remove everything that isn't permitted
    out = out.replace(/[^a-z0-9.-]/g, "");

    return out;
}

export function shuffleString(s)
{
    let a = s.split("");

    // Fisher-Yates shuffle, Durstenfeld version
    for (let first = a.length - 1; first > 0; first--) {
        const second = Math.floor(Math.random() * (first + 1));
        [a[first], a[second]] = [a[second], a[first]];
    }

    return a.join("");
}

export function buildUsernameFixingTable(data, alternateUmlauts)
{
    const firstCol = data.findColumn("first"),
          lastCol = data.findColumn("last"),
          uidCol = data.findColumn("uid");

    let usernames = new Set();

    let out = [];

    for (let rowNum = 0; rowNum < data.rows.length; rowNum++) {
        const values = data.rows[rowNum].cellValues;

        if (values[firstCol].trim().length == 0 ||
            values[lastCol].trim().length == 0 ||
            values[uidCol].trim().length == 0)
            continue;

        let first = values[firstCol].trim(),
            last = values[lastCol].trim(),
            uid = values[uidCol].trim();

        if (!usernames.has(uid)) {
            usernames.add(uid);
            continue;
        }

        // Regenerate duplicate name if the user has multiple first names
        const parts = first.split(" ").filter(i => i);

        if (parts.length < 2 || parts[1].trim().length == 0)
            continue;

        const newUID = dropDiacritics(`${parts[0]}.${parts[1][0]}.${last}`.toLowerCase(), alternateUmlauts);

        // Most of this data is for the preview
        out.push({
            row: rowNum,
            first: first,
            last: last,
            oldUID: uid,
            newUID: newUID
        });

        usernames.add(newUID);
    }

    return out;
}
