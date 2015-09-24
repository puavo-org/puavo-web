
import R from "ramda";
import {updateIn} from "updeep";
import cleanDiacritics from "underscore.string/cleanDiacritics";
import trim from "underscore.string/trim";

import ColumnTypes from "./ColumnTypes";
import {getCellValue, deepFreeze} from "./utils";

const initialState = deepFreeze({
    rows: [],
    rowStatus: {},
    defaultSchool: null,
    legacyRoles: [],
    autoOpenColumnEditor: null,
    columns: [
        ColumnTypes.first_name,
        ColumnTypes.last_name,
        ColumnTypes.email,
    ],
});

const usernameSlugify = R.compose(
    s => s.toLowerCase().replace(/[^a-z\.]/g, ""),
    R.partialRight(trim, ". "),
    cleanDiacritics
);

const arrayToObj = R.addIndex(R.reduce)((acc, val, i) => R.assoc(i, {originalValue: val}, acc), {});
const findLongestRowLength = R.compose(R.reduce(R.max, 0), R.map(R.prop("length")));
const appendUnknownColumns = R.compose(R.flip(R.concat), R.repeat(ColumnTypes.unknown), R.max(0));
const removeByIndex = R.remove(R.__, 1);

function reducer(state=initialState, action) {
    switch (action.type) {
    case "SET_IMPORT_DATA":
        return R.evolve({
            columns: appendUnknownColumns(findLongestRowLength(action.data) - state.columns.length),
            rows: R.always(action.data.map(arrayToObj)),
        }, state);
    case "SET_CUSTOM_VALUE":
        const usernameIndex = R.findIndex(isUsername, state.columns);
        var value = action.value;
        if (action.columnIndex === usernameIndex) {
            value = usernameSlugify(value);
        }
        return updateIn(["rows", action.rowIndex, action.columnIndex, "customValue"], value, state);
    case "ADD_COLUMN":
        return R.evolve({
            autoOpenColumnEditor: R.always(state.columns.length),
            columns: R.append(ColumnTypes[action.columnType]),
        }, state);
    case "CLEAR_AUTO_OPEN_COLUMN_EDITOR":
        return R.assoc("autoOpenColumnEditor", null, state);
    case "DROP_ROW":
        return R.evolve({
            rows: removeByIndex(action.rowIndex),
            rowStatus: R.omit([String(action.rowIndex)]),
        }, state);
    case "DROP_COLUMN":
        return R.evolve({columns: removeByIndex(action.columnIndex)}, state);
    case "CHANGE_COLUMN_TYPE":
        return updateIn(["columns", action.columnIndex], R.always(ColumnTypes[action.typeId]), state);
    case "SET_ROW_STATUS":
        return updateIn(["rowStatus", action.rowIndex], R.merge(R.__, R.omit(["type"], action)), state);
    case "SET_DEFAULT_SCHOOL":
        return R.assoc("defaultSchool", action.school, state);
    case "SET_LEGACY_ROLES":
        return R.assoc("legacyRoles", action.legacyRoles, state);
    case "FILL_COLUMN":
        return R.evolve({rows: R.addIndex(R.map)((row, rowIndex) => {
            if (R.path(["rowStatus", rowIndex, "status"], state) === "ok") {
                return row;
            }
            if (!action.override && getCellValue(row[action.columnIndex])) {
                return row;
            }
            return updateIn([action.columnIndex, "customValue"], action.value, row);
        })}, state);
    default:
        return state;
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


function injectUsernames(state) {
    if (!canGenerateUsername(state.columns)) return state;

    const usernameIndex = R.findIndex(isUsername, state.columns);
    const isMissingUsername = R.any(isMissing(usernameIndex));

    if (!isMissingUsername(state.rows)) return state;

    const addUsernames = R.map(generateDefaultUsername(
        usernameIndex,
        R.findIndex(isFirstName, state.columns),
        R.findIndex(isLastName, state.columns)
    ));

    return R.evolve({rows: addUsernames}, state);
}

export default R.compose(injectUsernames, reducer);


