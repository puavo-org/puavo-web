
import Papa from "papaparse";
import R from "ramda";

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
        return R.assoc(R.path([i, "attribute"], columns), getCellValue(cell), memo);
    }, {}),
    R.toPairs
);

export function startImport(rowIndex=0) {
    return (dispatch, getState) => {
        var {importData: {rows, columns}} = getState();

        if (rows.length < rowIndex) return;

        var restStyleData = rows.map(rowToRest(columns));
        console.log("DATA FOR REST: " + JSON.stringify(restStyleData, null, "  "));

        dispatch({
            type: "SET_SENDING_ROW",
            rowIndex,
        });

        setTimeout(() => {
            dispatch({
                type: "SET_OK_ROW",
                rowIndex,
            });
            dispatch(startImport(rowIndex + 1));
        }, 500);
    };
}
