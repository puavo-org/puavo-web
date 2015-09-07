
import R from "ramda";

const required = true;
const userAttribute = true;

const ColumnTypes = [
    {name: "First name", attribute: "first_name", id: "first_name", required, userAttribute},
    {name: "Last name", attribute: "last_name", id: "last_name", required, userAttribute},
    {name: "Email", attribute: "email", id: "email", userAttribute},
    {name: "Username", attribute: "username", id: "username", required, userAttribute},
    {name: "User type", attribute: "roles", id: "user_type", required, userAttribute},
    {name: "Role ID number", id: "legacy_role", required},
    {name: "Unkown", id: "unknown"},
    // {name: "Role (legacy)", attribute: "legacy_role"},
];

const toMapId = R.reduce((map, type) => R.assoc(type.id, type, map), {});

export const REQUIRED_COLUMNS = R.filter(R.propEq("required", true), ColumnTypes);

export default toMapId(ColumnTypes);
