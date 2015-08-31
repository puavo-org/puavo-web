
import R from "ramda";
import u from "updeep";
import cleanDiacritics from "underscore.string/cleanDiacritics";
import trim from "underscore.string/trim";

import COLUMN_TYPES from "./column_types";
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
        COLUMN_TYPES.first_name,
        COLUMN_TYPES.last_name,
        COLUMN_TYPES.email,
    ],
};

const arrayToObj = R.addIndex(R.reduce)((acc, val, i) => R.assoc(i, {originalValue: val}, acc), {});
const findLongestRowLength = R.compose(R.reduce(R.max, 0), R.map(R.prop("length")));
const appendUnknownColumns = R.compose(R.flip(R.concat), R.repeat(COLUMN_TYPES.unknown), R.max(0));
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
        return R.evolve({columns: R.append(COLUMN_TYPES[action.columnType])}, data);
    case "DROP_ROW":
        return R.evolve({rows: removeByIndex(action.rowIndex)}, data);
    case "CHANGE_COLUMN_TYPE":
        return u.updateIn(["columns", action.columnIndex], COLUMN_TYPES[action.typeId], data);
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

const isFirstName = R.equals(COLUMN_TYPES.first_name);
const isLastName = R.equals(COLUMN_TYPES.last_name);
const isUsername = R.equals(COLUMN_TYPES.username);
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
    const setStatus = R.assoc(action.rowIndex, R.__, states);

    switch (action.type) {
    case "SET_ROW_STATUS":
        return setStatus(R.omit(["type"], action));
    default:
        return states;
    }
}

export function defaultSchoolDn(schoolDn=null, action) {
    switch (action.type) {
    case "SET_DEFAULT_SCHOOL":
        return action.schoolDn;
    default:
        return schoolDn;
    }
}


