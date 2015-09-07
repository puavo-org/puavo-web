
import Bluebird from "bluebird";
const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]') .content;
const PROXY_PREFIX = "/restproxy";

export const BAD_HTTP_CODE = "BAD_HTTP_CODE";


async function request(method, path, data) {

    if (method !== "GET" && data) {
        data = JSON.stringify(data);
    }

    path = PROXY_PREFIX + path;

    console.log("fetch", method, path, data);

    var res = await Bluebird.resolve(window.fetch(path, {
        method,
        body: data,
        credentials: "same-origin",
        headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": CSRF_TOKEN,
        },
    }));


    if (res.status !== 200) {
        let error = new Error("Bad http status code");
        error.path = path;
        error.code = BAD_HTTP_CODE;
        error.res = res;
        throw error;
    }

    return res;

}

export function createUser(data) {
    return request("POST", "/v3/users", data);
}

export function replaceLegacyRoles(username, roleIds) {
    return request("PUT", `/v3/users/${username}/legacy_roles`, {ids: roleIds});
}

