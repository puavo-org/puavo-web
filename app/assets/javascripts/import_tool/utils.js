import { MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH } from "./constants.js";
import { clamp } from "../common/utils.js";

export function clampPasswordLength(value)
{
    return clamp(value, MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);
}

// Begins an async fetch() GET request for getting a list of current users and returns the
// promise. You must add the relevant then() parts to the chain and also handle errors.
export function beginGET(url)
{
    return fetch(url, {
        method: "GET",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
    }).then(response => {
        if (!response.ok)
            throw response;

        // By parsing the JSON in the "next" stage, we can handle errors better
        return response.text();
    });
}

// Like above, but for POST requests. Used like beginGET(), but you can supply optional
// request body (will be encoded in JSON).
export function beginPOST(url, body=null)
{
    return fetch(url, {
        method: "POST",
        mode: "cors",
        headers: {
            // Use text/plain to avoid RoR from logging the parameters in plain text.
            // They can contain passwords and other sensitive stuff.
            "Content-Type": "text/plain; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: (body !== null) ? JSON.stringify(body) : "",
    }).then(response => {
        if (!response.ok)
            throw response;

        // By parsing the JSON in the "next" stage, we can handle errors better
        return response.text();
    });
}

// All beginGET() and beginPOST() fetches return plain text. This utility function can
// be used to parse that into JSON. Handles errors, returns NULL if something fails.
export function parseServerJSON(text)
{
    try {
        return JSON.parse(text);
    } catch (e) {
        console.error("Can't parse the server response:");
        console.error(e);
        console.error(text);

        return null;
    }
}
