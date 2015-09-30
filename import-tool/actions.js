import Papa from "papaparse";
import R from "ramda";
import Bluebird from "bluebird";

import {
    ADD_COLUMN,
    CHANGE_COLUMN_TYPE,
    CLEAR_AUTO_OPEN_COLUMN_EDITOR,
    DROP_COLUMN,
    DROP_ROW,
    FILL_COLUMN,
    SET_CUSTOM_VALUE,
    SET_IMPORT_DATA,
    SET_LEGACY_ROLES,

    CREATE_USER,
    UPDATE_SCHOOL,
    UPDATE_ALL,
    KNOWN_UPDATE_TYPES,
} from "./constants";

import * as Api from "./Api";
import ColumnTypes from "./ColumnTypes";
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
    return {
        type: SET_CUSTOM_VALUE,
        rowIndex, columnIndex, value,
    };
}

export function fillColumn(columnIndex, value, override) {
    return {
        type: FILL_COLUMN,
        columnIndex, value, override,
    };
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

export function startImport(rowIndex=0) {
    return async (dispatch, getState) => {

        const {rows, columns, defaultSchool, rowStatus, legacyRoles} = getState();

        const next = R.compose(dispatch, R.partial(startImport, rowIndex + 1));
        const dispatchStatus = R.compose(dispatch, R.merge({
            type: "SET_ROW_STATUS",
            rowIndex,
        }));

        if (rows.length < rowIndex+1) return;

        const currentStatus = R.path([rowIndex], rowStatus) || {};

        if (currentStatus.status === "ok") {
            return next();
        }

        const row = rows[rowIndex];
        var userData = rowToRest(columns)(row);
        userData = R.assoc("school_dns", [defaultSchool.dn], userData);

        dispatchStatus({status: "working"});

        const updateTypeIndex = R.head(findIndices(ColumnTypes.update_type.id, columns));
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
                    return next();
                }

                dispatchStatus({
                    status: "error",
                    message: "User creation failed",
                    error,
                });
                return next();
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
                return next();
            }
            dispatchStatus({userUpdated: true, user});
        }

        const roleIndices = findIndices(ColumnTypes.legacy_role.id, columns);
        const roleNames = roleIndices.map(i => getCellValue(row[i]));
        const roleIds = roleNames
            .map(name => legacyRoles.find(r => r.name === name))
            .map(r => r.id);

        try {
            await Api.replaceLegacyRoles(userData.username, roleIds);
        } catch(error) {
            dispatchStatus({
                status: "error",
                message: "Failed to set legacy roles",
                error,
            });
            return next();
        }

        dispatchStatus({status: "ok"});
        return next();
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
