
import R from "ramda";
import React from "react";

import {deepFreeze} from "./utils";

const required = true;

// Whether the type maps directly to puavo-rest user attribute
const userAttribute = true;

const ColumnTypes = deepFreeze([
    {attribute: "first_name", id: "first_name", required, userAttribute},
    {attribute: "last_name", id: "last_name", required, userAttribute},
    {attribute: "email", id: "email", userAttribute},
    {attribute: "username", id: "username", required, userAttribute},
    {attribute: "roles", id: "role", required, userAttribute},
    {attribute: "password", id: "password", userAttribute},
    {id: "legacy_role", required},
    {id: "group", required},
    {id: "update_type"},
    {id: "unknown"},
]);

export const ReactColumnType = React.PropTypes.shape({
    id: React.PropTypes.string.isRequired,
    type: React.PropTypes.string,
});

const toMapId = R.reduce((map, type) => R.assoc(type.id, type, map), {});

export const pickRequiredColumns = R.compose(
    R.filter(R.propEq("required", true)),
    R.values
);

export const AllColumnTypes = toMapId(ColumnTypes);
