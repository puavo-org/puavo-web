
import Papa from "papaparse";
import R from "ramda";

import COLUMN_TYPES from "./column_types";
import {getCellValue} from "./utils";

export function setImportData(rawCSV) {
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

const rowToRest = columns => R.compose(
    R.reduce((memo, [i, cell]) => {
        var restAttr = columns[i];
        if (restAttr === COLUMN_TYPES.unknown) return memo;
        return R.assoc(restAttr.attribute, getCellValue(cell), memo);
    }, {}),
    R.toPairs
);

const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]') .content;

export function startImport(rowIndex=0) {
    return async (dispatch, getState) => {

        var {importData: {rows, columns}} = getState();

        const next = () => dispatch(startImport(rowIndex + 1));

        if (rows.length < rowIndex) return;

        var restStyleData = rows.map(rowToRest(columns));
        console.log("DATA FOR REST: " + JSON.stringify(restStyleData, null, "  "));

        dispatch({
            type: "SET_ROW_STATUS",
            status: "starting",
            rowIndex,
        });
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
            dispatch({
                type: "SET_ROW_STATUS",
                status: "error",
                error,
                rowIndex,
            });
            console.log("starting next");
            return next();
        }

        var data = await res.json();

        dispatch({
            type: "SET_ROW_STATUS",
            status: `status ${res.status}`,
            data,
            rowIndex,
        });

        next();
    };
}
