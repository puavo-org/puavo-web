
import Papa from "papaparse";

export function setImportData(rawCSV) {
    var res = Papa.parse(rawCSV);
    // XXX: Assert res.errors


    return {
        type: "SET_IMPORT_DATA",
        data: res.data,
    };

}
