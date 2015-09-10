
import Bluebird from "bluebird";
const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]') .content;
const PROXY_PREFIX = "/restproxy";

export const BAD_HTTP_CODE = "BAD_HTTP_CODE";
export const BAD_JSON = "BAD_JSON";


async function request(method, path, data) {

    if (method !== "GET" && data) {
        data = JSON.stringify(data);
    }

    path = PROXY_PREFIX + path;

    console.log("fetch", method, path, data);

    const res = await Bluebird.resolve(window.fetch(path, {
        method,
        body: data,
        credentials: "same-origin",
        headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": CSRF_TOKEN,
        },
    }));

    let responseData = null;

    try {
        responseData = await res.json();
    } catch(parseError) {
        let error = new Error("Failed to parse JSON");
        error.path = path;
        error.code = BAD_JSON;
        error.res = res;
        throw error;
    }


    if (res.status !== 200) {
        let error = new Error("Bad http status code");
        error.path = path;
        error.code = BAD_HTTP_CODE;
        error.data = responseData;
        error.res = res;
        throw error;
    }

    return responseData;
}

export function createUser(data) {
    return request("POST", "/v3/users", data);
}

export function replaceLegacyRoles(username, roleIds) {
    return request("PUT", `/v3/users/${username}/legacy_roles`, {ids: roleIds});
}

export function fetchLegacyRoles(schoolId) {
    return request("GET", `/v3/schools/${schoolId}/legacy_roles`);
}

export function createPasswordResetIntent(schoolId, userIds) {
    return request("POST", `/v3/schools/${schoolId}/user_lists`, {ids: userIds});
}

