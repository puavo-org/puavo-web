export function dropDiacritics(string, alternateUmlauts)
{
    let out = string;

    if (alternateUmlauts) {
        // Convert some umlauts differently. These conversions won't work in Finnish,
        // but they work in some other languages.
        out = out.replace(/ä/g, "ae");
        out = out.replace(/ö/g, "oe");
        out = out.replace(/ü/g, "ue");
    }

    // Leaving this out will cause trouble (and the old version did this too)
    out = out.replace(/ß/g, "ss");

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
