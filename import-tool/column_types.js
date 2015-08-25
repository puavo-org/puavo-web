
import R from "ramda";

const COLUMN_TYPES = [
    {name: "First name", attribute: "first_name", id: "first_name"},
    {name: "Last name", attribute: "last_name", id: "last_name"},
    {name: "Email", attribute: "email", id: "email"},
    {name: "Username", attribute: "username", id: "username"},
    {name: "User type", attribute: "roles", id: "user_type"},
    {name: "Unkown", id: "unknown"},
    // {name: "Role (legacy)", attribute: "legacy_role"},
];

const toMapId = R.reduce((map, type) => R.assoc(type.id, type, map), {});

export default toMapId(COLUMN_TYPES);
