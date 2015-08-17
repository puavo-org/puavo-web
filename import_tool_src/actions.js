
import Papa from "papaparse";
import R from "ramda";

export function setImportData(rawCSV) {
    var res = Papa.parse(rawCSV.trim());
    // XXX: Assert res.errors


    return {
        type: "SET_IMPORT_DATA",
        data: res.data,
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

export function startImport() {
    return (dispatch, getState) => {
        var {columnTypes, importData} = getState();

        var restStyleData = importData.map(row => row.reduce((memo, cell, i) => {
            var value = cell.customValue || cell.originalValue;
            return R.assoc(R.path([i, "attribute"], columnTypes), value, memo);
        }, {}));

        console.log("DATA FOR REST: " + JSON.stringify(restStyleData, null, "  "));


    };
}
