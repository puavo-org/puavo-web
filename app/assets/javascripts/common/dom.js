// The Swiss Army document.createElement wrapper. Sets all the attributes and other things
// you want, in one function call!
export function create(tag, params={})
{
    let e = document.createElement(tag);

    if ("id" in params && params.id !== undefined)
        e.id = params.id;

    if ("cls" in params && params.cls !== undefined) {
        if (Array.isArray(params.cls))
            e.className = params.cls.join(" ");
        else e.className = params.cls;
    }

    if ("html" in params && params.html !== undefined)
        e.innerHTML = params.html;

    if ("text" in params && params.text !== undefined)
        e.innerText = params.text;

    if ("textnode" in params && params.textnode !== undefined)
        e.appendChild(document.createTextNode(params.textnode));

    if ("title" in params && params.title !== undefined)
        e.title = params.title;

    if ("label" in params && params.label !== undefined)
        e.label = params.label;

    if ("inputType" in params && params.inputType !== undefined)
        e.type = params.inputType;

    if ("inputValue" in params && params.inputValue !== undefined)
        e.value = params.inputValue;

    return e;
}

export function destroy(e)
{
    if (e)
        e.remove();
}

// Returns a usable copy of a named HTML template. It's a DocumentFragment, not text,
// so it must be handled with DOM methods.
export function getTemplate(id)
{
    return document.querySelector(`template#template_${id}`).content.cloneNode(true);
}

// Adds or removes 'cls' from target's classList, depending on 'state' (true=add, false=remove)
export function toggleClass(target, cls, state)
{
    if (!target) {
        console.error(`toggleClass(): target element is NULL! (cls="${cls}", state=${state})`);
        return;
    }

    if (state)
        target.classList.add(cls);
    else target.classList.remove(cls);
}
