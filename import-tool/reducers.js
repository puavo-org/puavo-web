
import R from "ramda";
import u from "updeep";
import cleanDiacritics from "underscore.string/cleanDiacritics";
import trim from "underscore.string/trim";

import ColumnTypes from "./ColumnTypes";
import {getCellValue} from "./utils";

const usernameSlugify = R.compose(
    s => s.toLowerCase().replace(/[^a-z\.]/g, ""),
    R.partialRight(trim, ". "),
    cleanDiacritics
);

const initialImportData = {
    rows: [],
    defaultValues: {},
    columns: [
        ColumnTypes.first_name,
        ColumnTypes.last_name,
        ColumnTypes.email,
    ],
};

const arrayToObj = R.addIndex(R.reduce)((acc, val, i) => R.assoc(i, {originalValue: val}, acc), {});
const findLongestRowLength = R.compose(R.reduce(R.max, 0), R.map(R.prop("length")));
const appendUnknownColumns = R.compose(R.flip(R.concat), R.repeat(ColumnTypes.unknown), R.max(0));
const removeByIndex = R.remove(R.__, 1);


function importData_(data=initialImportData, action) {
    switch (action.type) {
    case "SET_IMPORT_DATA":
        return R.evolve({
            columns: appendUnknownColumns(findLongestRowLength(action.data) - data.columns.length),
            rows: R.always(action.data.map(arrayToObj)),
        }, data);
    case "SET_CUSTOM_VALUE":
        const usernameIndex = R.findIndex(isUsername, data.columns);
        var value = action.value;
        if (action.columnIndex === usernameIndex) {
            value = usernameSlugify(value);
        }
        return u.updateIn(["rows", action.rowIndex, action.columnIndex, "customValue"], value, data);
    case "ADD_COLUMN":
        return R.evolve({columns: R.append(ColumnTypes[action.columnType])}, data);
    case "DROP_ROW":
        return R.evolve({rows: removeByIndex(action.rowIndex)}, data);
    case "DROP_COLUMN":
        return R.evolve({columns: removeByIndex(action.columnIndex)}, data);
    case "CHANGE_COLUMN_TYPE":
        return u.updateIn(["columns", action.columnIndex], ColumnTypes[action.typeId], data);
    case "SET_DEFAULT_VALUE":
        return R.evolve({rows: R.map(row => {
            if (getCellValue(row[action.columnIndex])) return row;
            return u.updateIn([action.columnIndex, "customValue"], action.value, row);
        })}, data);
    default:
        return data;
    }
}

const rowValue = R.curry((index, row) => getCellValue(row[index]));
const isMissing = R.curry((index, row) => !getCellValue(row[index]));

const isFirstName = R.equals(ColumnTypes.first_name);
const isLastName = R.equals(ColumnTypes.last_name);
const isUsername = R.equals(ColumnTypes.username);
const canGenerateUsername = R.allPass(R.map(R.any, [isFirstName, isLastName, isUsername]));

const generateDefaultUsername = R.curry((usernameIndex, firstNameIndex, lastNameIndex, row) => {
    if (rowValue(usernameIndex, row)) return row;
    var username = [firstNameIndex, lastNameIndex]
        .map(i => usernameSlugify(rowValue(i, row)))
        .join(".");
    return R.over(R.lensProp(usernameIndex), R.assoc("customValue", username), row);
});


function injectUsernames(data) {
    if (!canGenerateUsername(data.columns)) return data;

    const usernameIndex = R.findIndex(isUsername, data.columns);
    const isMissingUsername = R.any(isMissing(usernameIndex));

    if (!isMissingUsername(data.rows)) return data;

    const addUsernames = R.map(generateDefaultUsername(
        usernameIndex,
        R.findIndex(isFirstName, data.columns),
        R.findIndex(isLastName, data.columns)
    ));

    return R.evolve({rows: addUsernames}, data);
}

export const importData = R.compose(injectUsernames, importData_);

export function rowStatus(states={}, action) {
    if (action.type !== "SET_ROW_STATUS") return states;
    return R.over(
        R.lensProp(action.rowIndex),
        R.merge(R.__, R.omit(["type"], action)),
        states
    );
}

export function defaultSchoolDn(schoolDn=null, action) {
    switch (action.type) {
    case "SET_DEFAULT_SCHOOL":
        return action.schoolDn;
    default:
        return schoolDn;
    }
}


