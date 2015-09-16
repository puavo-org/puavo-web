import Papa from "papaparse";
import R from "ramda";
import Bluebird from "bluebird";

import * as Api from "./Api";
import ColumnTypes from "./ColumnTypes";
import {getCellValue} from "./utils";
import {resetState} from "./StateStorage";


export function parseImportString(rawCSV) {
    var res = Papa.parse(rawCSV.trim());
    // XXX: Assert res.errors


    return {
        type: "SET_IMPORT_DATA",
        data: res.data,
    };

}

export function addColumn(columnType) {
    return {
        type: "ADD_COLUMN",
        columnType,
    };
}

export function changeColumnType(columnIndex, typeId) {
    return {
        type: "CHANGE_COLUMN_TYPE",
        columnIndex, typeId,
    };
}

export function setCustomValue(rowIndex, columnIndex, value) {
    return {
        type: "SET_CUSTOM_VALUE",
        rowIndex, columnIndex, value,
    };
}

export function fillColumn(columnIndex, value, override) {
    return {
        type: "FILL_COLUMN",
        columnIndex, value, override,
    };
}

export function dropRow(rowIndex) {
    return {
        type: "DROP_ROW",
        rowIndex,
    };
}

export function dropColumn(columnIndex) {
    return {
        type: "DROP_COLUMN",
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

        const {rows, columns, defaultSchool, rowStatus} = getState();

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

        const changeSchoolIndex = R.head(findIndices(ColumnTypes.change_school.id, columns));
        let changeSchoolForExistingUser = false;
        if (!R.isNil(changeSchoolIndex)) {
            changeSchoolForExistingUser = !!getCellValue(row[changeSchoolIndex]);
        }

        if (!changeSchoolForExistingUser && !currentStatus.created) {
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

        if (changeSchoolForExistingUser) {
            try {
                await Api.updateUser(userData.username, {school_dns: [defaultSchool.dn]});
            } catch(error) {
                dispatchStatus({
                    status: "error",
                    message: "Failed to change school",
                    error,
                });
                return next();
            }
            dispatchStatus({schoolChanged: true});
        }

        const roleIndices = findIndices(ColumnTypes.legacy_role.id, columns);
        const roleIds = roleIndices.map(i => getCellValue(row[i]));

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

export function createPasswordResetIntentForNewUsers() {
    return async (dispatch, getState) => {

        const {rowStatus, defaultSchool} = getState();
        const newUserIds = getNewUsers(rowStatus);

        await Api.createPasswordResetIntent(defaultSchool.id, newUserIds);

        dispatch(resetState());

        await Bluebird.delay(1);
        window.location = `/users/${defaultSchool.id}/lists`;
    };
}

export function fetchLegacyRoles(schoolId) {
    return async (dispatch) => {
        const legacyRoles = await Api.fetchLegacyRoles(schoolId);
        dispatch({
            type: "SET_LEGACY_ROLES",
            legacyRoles,
        });
    };
}
