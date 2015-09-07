import Papa from "papaparse";
import R from "ramda";

import Api from "./Api";
import ColumnTypes from "./ColumnTypes";
import {getCellValue} from "./utils";


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
    R.path(["error", "code"])
);

function findIndices(id, columns) {
    return R.addIndex(R.reduce)((arr, columnType, i) => {
        return id === columnType.id ? arr.concat(i) : arr;
    }, [], columns);
}

export function startImport(rowIndex=0) {
    return async (dispatch, getState) => {

        const {importData: {rows, columns}, defaultSchoolDn, rowStatus} = getState();

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
        userData = R.assoc("school_dns", [defaultSchoolDn], userData);

        dispatchStatus({status: "working"});

        if (!currentStatus.created) {
            let res;

            try {
                res = await Api.createUser(userData);
            } catch(error) {
                dispatchStatus({status: "error", error});
                return next();
            }

            let responseData;

            try {
                responseData = await res.json();
            } catch(error) {
                dispatchStatus({status: "error", error});
                return next();
            }

            if (res.status === 400 && isValidationError(responseData)) {
                console.error("Validation error", responseData);
                dispatchStatus({
                    status: "error",
                    attributeErrors: responseData.error.meta.invalid_attributes,
                });
                return next();
            }

            dispatchStatus({created: true});
        }

        const roleIndices = findIndices(ColumnTypes.legacy_role.id, columns);
        const roleIds = roleIndices.map(i => getCellValue(row[i]));

        try {
            await Api.replaceLegacyRoles(userData.username, roleIds);
        } catch(error) {
            dispatchStatus({
                status: "error",
                message: error.message,
            });
            return next();
        }

        dispatchStatus({status: "ok"});
        return next();
    };
}
