// A shorter to type alias
export function _tr(id, params={})
{
    return I18n.translate(id, params);
}

export function pad(number, len=2)
{
    return String(number).padStart(len, "0");
}

export function escapeHTML(s)
{
    if (typeof(s) != "string")
        return s;

    // I wonder how safe/reliable this is?
    return s.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
}

// Math.clamp() does not exist at the moment
export function clamp(value, min, max)
{
    return Math.min(Math.max(min, value), max);
}
