
import R from "ramda";

export function importData(data=[], action) {
    if (action.type !== "SET_IMPORT_DATA") return data;
    return action.data;
}


export function columnTypes(columnTypes, action) {
    if (!columnTypes) {
        return [
            {attribute: "first_name"},
            {attribute: "last_name"},
            {attribute: "username"},
        ];
    }

    switch (action.type) {
        case "ADD_COLUMN":
            return R.append(action.columnType, columnTypes);
        default:
            return columnTypes;
    }

}
