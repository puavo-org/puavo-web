import Papa from "papaparse";
import R from "ramda";
import Bluebird from "bluebird";
import Piecon from "piecon";

import t from "./i18n";

import {
    ADD_COLUMN,
    CHANGE_COLUMN_TYPE,
    CLEAR_AUTO_OPEN_COLUMN_EDITOR,
    DROP_COLUMN,
    DROP_ROW,
    FILL_COLUMN,
    SET_ACTIVE_COLUMN_TYPES,
    SET_CUSTOM_VALUE,
    SET_GROUPS,
    SET_IMPORT_DATA,
    SET_LEGACY_ROLES,
    SET_USER_DATA,

    CREATE_USER,
    UPDATE_SCHOOL,
    UPDATE_ALL,
    KNOWN_UPDATE_TYPES,
} from "./constants";

import * as Api from "./Api";
import {AllColumnTypes} from "./ColumnTypes";
import {getCellValue} from "./utils";
import {resetState} from "./StateStorage";



export function parseImportString(rawCSV) {
    var res = Papa.parse(rawCSV.trim());
    // XXX: Assert res.errors


    return {
        type: SET_IMPORT_DATA,
        data: res.data,
    };

}

export function clearAutoOpenColumnEditor() {
    return {type: CLEAR_AUTO_OPEN_COLUMN_EDITOR};
}

export function addColumn(columnType) {
    return {
        type: ADD_COLUMN,
        columnType,
    };
}

export function changeColumnType(columnIndex, typeId) {
    return {
        type: CHANGE_COLUMN_TYPE,
        columnIndex, typeId,
    };
}

export function setCustomValue(rowIndex, columnIndex, value) {
    return (dispatch) => {
        dispatch({
            type: SET_CUSTOM_VALUE,
            rowIndex, columnIndex, value,
        });
    };
}

export function fillColumn(columnIndex, value, override) {
    return (dispatch, getState) => {
        dispatch({
            type: FILL_COLUMN,
            columnIndex, value, override,
        });
    };
}

const isNotFoundError = (e) => R.pathEq(["res", "status"], 404, e);
var fetchingUsernames = false;

export function setVisibleUsernames(curretlyVisibleUsernames) {
    return async (dispatch, getState) => {
        dispatch({
            type: "SET_VISIBLE_USERNAMES",
            visibleUsernames: curretlyVisibleUsernames,
        });

        if (fetchingUsernames) return;
        fetchingUsernames = true;

        let activeJobs = [];

        while (true) {
            activeJobs = activeJobs.filter(a => a.isPending());

            let {visibleUsernames, userCache} = getState();
            let unknownVisibleUsernames = visibleUsernames.filter(username => !userCache[username]);
            if (unknownVisibleUsernames.length === 0) break;

            console.log("Fetching usernames", JSON.stringify(unknownVisibleUsernames));

            if (activeJobs.length > 2) {
                await Bluebird.race(activeJobs);
                continue;
            }

            activeJobs.push(fetchUserData(unknownVisibleUsernames[0], dispatch));
        }

        fetchingUsernames = false;
    };
}

async function fetchUserData(username, dispatch) {
    dispatch({
        username,
        type: SET_USER_DATA,
        state: "fetching",
    });

    try {
        dispatch({
            type: SET_USER_DATA,
            username,
            state: "ok",
            userData: await Api.fetchUserData(username),
        });
    } catch (error) {
        let state = "error";
        if (isNotFoundError(error)) {
            state = "notfound";
        } else {
            console.error("Unkown user fetch error", error);
        }
        dispatch({
            username,
            type: SET_USER_DATA,
            state,
        });
    }
}


export function dropRow(rowIndex) {
    return {
        type: DROP_ROW,
        rowIndex,
    };
}

export function dropColumn(columnIndex) {
    return {
        type: DROP_COLUMN,
        columnIndex,
    };
}

const rowToRest = columns => R.compose(
    R.reduce((memo, [i, cell]) => {
        var restAttr = columns[i];
        if (!restAttr.userAttribute) return memo;

        var val = getCellValue(cell);
        if (restAttr.attribute === "roles") {
            val = [val];
        }

        return R.assoc(restAttr.attribute, val, memo);
    }, {}),
    R.toPairs
);


const isValidationError = R.compose(
    R.equals("ValidationError"),
    R.path(["data", "error", "code"])
);

const getValidationErrors = R.compose(
    R.defaultTo([]),
    R.path(["data", "error", "meta", "invalid_attributes"])
);

function findIndices(id, columns) {
    return R.addIndex(R.reduce)((arr, columnType, i) => {
        return id === columnType.id ? arr.concat(i) : arr;
    }, [], columns);
}

function preventUnload(e) {
    const msg = t("prevent_unload");
    e.returnValue = msg;
    return msg;
}

export function startImport() {
    return async (dispatch, getState) => {

        window.addEventListener("beforeunload", preventUnload);
        let rowIndex = -1;

        Piecon.setOptions({
            color: "#FAB32E",
            background: "#bbb",
            shadow: "#fff",
        });
        Piecon.setProgress(0);

        while (true) {

            const {
                rows,
                columns,
                defaultSchool,
                rowStatus,
                legacyRoles,
                groups,
            } = getState();

            Piecon.setProgress(Math.round(rowIndex / rows.length * 100));

            rowIndex++;

            const dispatchStatus = R.compose(dispatch, R.merge({
                type: "SET_ROW_STATUS",
                rowIndex,
            }));

            if (rows.length < rowIndex+1) break;

            const currentStatus = R.path([rowIndex], rowStatus) || {};

            if (currentStatus.status === "ok") continue;

            const row = rows[rowIndex];
            let userData = rowToRest(columns)(row);
            userData = R.assoc("school_dns", [defaultSchool.dn], userData);

            dispatchStatus({status: "working"});

            const updateTypeIndex = R.head(findIndices(AllColumnTypes.update_type.id, columns));
            const updateType = KNOWN_UPDATE_TYPES[getCellValue(row[updateTypeIndex])] || CREATE_USER;

            if (updateType === CREATE_USER && !currentStatus.created) {
                let user = null;
                try {
                    user = await Api.createUser(userData);
                } catch(error) {
                    if (isValidationError(error)) {
                        dispatchStatus({
                            status: "error",
                            attributeErrors: getValidationErrors(error),
                        });
                        continue;
                    }

                    dispatchStatus({
                        status: "error",
                        message: "User creation failed",
                        error,
                    });
                    continue;
                }

                dispatchStatus({created: true, user});
            }

            if ([UPDATE_SCHOOL, UPDATE_ALL].includes(updateType)) {
                let user = null;
                const updateData = updateType === UPDATE_SCHOOL
                    ? {school_dns: userData.school_dns}
                    : userData;

                try {
                    user = await Api.updateUser(userData.username, updateData);
                } catch(error) {
                    let message = "Failed to change school";
                    if (error.res.status === 404) {
                        message = "Cannot change school for unknown user";
                    }

                    dispatchStatus({
                        status: "error",
                        message,
                        error,
                    });
                    continue;
                }
                dispatchStatus({userUpdated: true, user});
            }

            const roleIndices = findIndices(AllColumnTypes.legacy_role.id, columns);
            const roleNames = roleIndices.map(i => getCellValue(row[i]));
            const roleIds = roleNames
                .map(name => legacyRoles.find(r => r.name === name))
                .map(r => r.id);

            if (roleIds.length > 0) {
                try {
                    await Api.replaceLegacyRoles(userData.username, roleIds);
                } catch(error) {
                    dispatchStatus({
                        status: "error",
                        message: "Failed to set legacy roles",
                        error,
                    });
                    continue;
                }
            }

            const groupIndices = findIndices(AllColumnTypes.group.id, columns);
            const groupAbbreviations = groupIndices.map(i => getCellValue(row[i]));
            const groupIds = groupAbbreviations
                .map(abbreviation => groups.find(g => g.abbreviation === abbreviation))
                .map(g => g.id);

            if (groupIds.length > 0) {
                try {
                    await Api.replaceGroups(userData.username, groupIds);
                } catch(error) {
                    dispatchStatus({
                        status: "error",
                        message: "Failed to set groups",
                        error,
                    });
                    continue;
                }
            }

            dispatchStatus({status: "ok"});

        }

        Piecon.setProgress(100);
        window.removeEventListener("beforeunload", preventUnload);
    };
}

const getNewUsers = R.compose(
    R.map(R.path(["user", "id"])),
    R.filter(R.propEq("created", true)),
    R.values
);

const getAllUsers = R.compose(
    R.map(R.path(["user", "id"])),
    R.values
);

export function createPasswordResetIntentForNewUsers({resetAll}) {
    return async (dispatch, getState) => {

        const {rowStatus, defaultSchool} = getState();
        let userIds = null;

        if (resetAll) {
            userIds = getAllUsers(rowStatus);
        } else {
            userIds = getNewUsers(rowStatus);
        }

        await Api.createPasswordResetIntent(defaultSchool.id, userIds);

        dispatch(resetState());

        await Bluebird.delay(1);
        window.location = `/users/${defaultSchool.id}/lists`;
    };
}

export function fetchLegacyRoles(schoolId) {
    return async (dispatch) => {
        const legacyRoles = await Api.fetchLegacyRoles(schoolId);
        dispatch({
            type: SET_LEGACY_ROLES,
            legacyRoles,
        });
    };
}

export function fetchGroups(schoolId) {
    return async (dispatch) => {
        const groups = await Api.fetchGroups(schoolId);
        dispatch({
            type: SET_GROUPS,
            groups,
        });
    };
}

export function setActiveColumnTypes(columnTypes) {
    return {
        type: SET_ACTIVE_COLUMN_TYPES,
        columnTypes,
    };
}
