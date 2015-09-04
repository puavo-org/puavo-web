
import Bluebird from "bluebird";
const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]') .content;
const PROXY_PREFIX = "/restproxy";


function request(method, path, data) {

    if (method !== "GET" && data) {
        data = JSON.stringify(data);
    }

    path = PROXY_PREFIX + path;

    console.log("fetch", method, path, data);

    return Bluebird.resolve(window.fetch(path, {
        method,
        body: data,
        credentials: "same-origin",
        headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": CSRF_TOKEN,
        },
    }));
}


export default {

    createUser(data) {
        return request("POST", "/v3/users", data);
    },

    replaceLegacyRoles(username, roleIds) {
        return request("PUT", `/v3/users/${username}/legacy_roles`, {ids: roleIds});
    },

};
