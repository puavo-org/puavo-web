import Papa from "papaparse";
import R from "ramda";

import ColumnTypes from "./ColumnTypes";
import {getCellValue} from "./utils";

const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]') .content;

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

export function setDefaultValue(columnIndex, value) {
    return {
        type: "SET_DEFAULT_VALUE",
        columnIndex, value,
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
        if (restAttr === ColumnTypes.unknown) return memo;
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

export function startImport(rowIndex=0) {
    return async (dispatch, getState) => {

        var {importData: {rows, columns}, defaultSchoolDn, rowStatus} = getState();

        const next = R.compose(dispatch, R.partial(startImport, rowIndex + 1));
        const dispatchStatus = R.compose(dispatch, R.merge({
            type: "SET_ROW_STATUS",
            rowIndex,
        }));

        if (rows.length < rowIndex+1) return;

        const currentStatus = R.path([rowIndex, "status"], rowStatus);
        console.log("Current status", rowIndex, currentStatus);

        if (currentStatus === "ok") {
            return next();
        }

        var restStyleData = rows.map(rowToRest(columns));
        restStyleData = R.map(R.assoc("school_dns", [defaultSchoolDn]), restStyleData);

        console.log("DATA FOR REST: " + JSON.stringify(restStyleData, null, "  "));

        dispatchStatus({status: "starting"});

        var res;

        var body = JSON.stringify(restStyleData[rowIndex]);
        console.log("sending body", body);

        try {
            res = await window.fetch("/restproxy/v3/users", {
                body,
                method: "post",
                credentials: "same-origin",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": CSRF_TOKEN,
                },
            });
        } catch(error) {
            dispatchStatus({status: "fetch error", error});
            return next();
        }

        var responseData;

        try {
            responseData = await res.json();
        } catch(error) {
            dispatchStatus({status: "failed to parse response json", error});
            return next();
        }

        if (res.status === 200) {
            dispatchStatus({status: "ok"});
            return next();
        }

        if (res.status === 400 && isValidationError(responseData)) {
            console.error("Validation error", responseData);
            dispatchStatus({
                status: "Validation error",
                attributeErrors: responseData.error.meta.invalid_attributes,
            });
            return next();
        }

        console.error("Unkown error", responseData);
        dispatchStatus({status: "Unkown error", responseData});
        next();
    };
}
