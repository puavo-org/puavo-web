// For new users, you need at least these columns
export const REQUIRED_COLUMNS_NEW = new Set(["first", "last", "uid", "role"]);

// The same as above, but for existing users (when updating their attributes)
export const REQUIRED_COLUMNS_UPDATE = new Set(["uid"]);

// Inferred column types. Maps various alternative colum name variants to one "unified" name.
// If the unified (inferred) name does not exist in LOCALIZED_COLUMN_TITLES, bad things will
// happen. So don't do that. The table contains even non-inferred names (usually the first
// entry for that column), so that we can convert all incoming column names through this table.
export const INFERRED_NAMES = {
    "first": "first",
    "first_name": "first",
    "firstname": "first",
    "first name": "first",
    "vorname": "first",
    "etunimi": "first",

    "last": "last",
    "last_name": "last",
    "lastname": "last",
    "last name": "last",
    "name": "last",
    "sukunimi": "last",

    "uid": "uid",
    "user_name": "uid",
    "username": "uid",
    "user name": "uid",
    "käyttäjätunnus": "uid",
    "käyttäjänimi": "uid",

    "role": "role",
    "type": "role",
    "rooli": "role",
    "tyyppi": "role",

    "phone": "phone",
    "telephone": "phone",
    "telefon": "phone",
    "puhelin": "phone",

    "email": "email",
    "mail": "email",

    "eid": "eid",
    "external_id": "eid",
    "externalid": "eid",
    "ulkoinen id": "eid",
    "sotuhash": "eid",

    "password": "password",
    "passwort": "password",
    "salasana": "password",
    "pwd": "password",

    "ryhmä": "group",

    "raw_group": "rawgroup",
    "raw group": "rawgroup",
    "raakaryhmä": "rawgroup",
};

// How many header columns each row has on the left edge. The status column is part of these.
export const NUM_ROW_HEADERS = 2;

// Batching size for the import process. Reduces the number of network calls, but makes the UI
// seem slower (as it's not updated very often).
export const BATCH_SIZE = 5;

// Password length limitations
export const MIN_PASSWORD_LENGTH = 8,
             MAX_PASSWORD_LENGTH = 100;

// Validation regexps. I'm not sure about the email and phone number regexps, but they're the same
// regexps we've used elsewhere (I think the telephone validator lets through too much junk).
export const USERNAME_REGEXP = /^[a-z][a-z0-9_.-]{2,}$/,
             EMAIL_REGEXP = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
             PHONE_REGEXP = /^\+?[A-Za-z0-9 '(),-.\/:?"]+$/;

export const VALID_ROLES = new Set(["student", "teacher", "staff", "parent", "visitor", "testuser"]);

// Row flags (stored in row.rowFlags)
export const RowFlag = {
    SELECTED: 0x01,
}

// Row states (used during the import process)
export const RowState = {
    IDLE: 1,
    PROCESSING: 2,
    SUCCESS: 3,
    PARTIAL_SUCCESS: 4,
    FAILED: 5,
};

// Cell flags
export const CellFlag = {
    SELECTED: 0x01,
    INVALID: 0x02,      // there's something wrong with this cell's value
};

// Duplicates finding mode
export const Duplicates = {
    ALL: 1,
    THIS_SCHOOL: 2,
    OTHER_SCHOOLS: 3,
};

// Row import mode
export const ImportRows = {
    ALL: 1,
    SELECTED: 2,
    FAILED: 3,
};

// Possible values for the popup attachment type
export const PopupType = {
    COLUMN_TOOL: 1,
    POPUP_MENU: 2,      // like COLUMN_TOOL, but the computed position is different
    CELL_EDIT: 3,
};
