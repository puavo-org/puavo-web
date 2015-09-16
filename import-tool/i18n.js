
/* global I18n */

if (typeof I18n === "undefined") {
    throw new Error("I18n is not loaded");
}

if (typeof I18n.t !== "function") {
    throw new Error("I18n translation library is not loaded properly");
}


export default function translate(key, ...args) {
    return I18n.t(`import_tool.${key}`, ...args);
}
