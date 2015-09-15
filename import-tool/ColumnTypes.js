
import R from "ramda";
import React from "react";

import {deepFreeze} from "./utils";

const required = true;
const userAttribute = true;

const ColumnTypes = deepFreeze([
    {name: "First name", attribute: "first_name", id: "first_name", required, userAttribute},
    {name: "Last name", attribute: "last_name", id: "last_name", required, userAttribute},
    {name: "Email", attribute: "email", id: "email", userAttribute},
    {name: "Username", attribute: "username", id: "username", required, userAttribute},
    {name: "User type", attribute: "roles", id: "role", required, userAttribute},
    {name: "Legacy Role", id: "legacy_role", required},
    {name: "Unkown", id: "unknown"},
    // {name: "Role (legacy)", attribute: "legacy_role"},
]);

export const ReactColumnType = React.PropTypes.shape({
    id: React.PropTypes.string.isRequired,
    name: React.PropTypes.string.isRequired,
    type: React.PropTypes.string,
});

const toMapId = R.reduce((map, type) => R.assoc(type.id, type, map), {});

export const REQUIRED_COLUMNS = deepFreeze(R.filter(R.propEq("required", true), ColumnTypes));

export default toMapId(ColumnTypes);
