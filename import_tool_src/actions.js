
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

export function startImport() {
    return (dispatch, getState) => {
        var {columnTypes, importData} = getState();

        var restStyleData = importData.map(row => row.reduce((memo, cell, i) => {
            return R.assoc(R.path([i, "attribute"], columnTypes), cell.originalValue, memo);
        }, {}));

        console.log("DATA FOR REST: " + JSON.stringify(restStyleData, null, "  "));


    };
}
