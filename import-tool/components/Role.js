
import React from "react";
import PureComponent from "./PureComponent";

import t from "../i18n";

import ErrorModalButton from "./ErrorModalButton";

const ROLES = [
    "teacher",
    "staff",
    "student",
    "visitor",
    "parent",
    "admin",
    "testuser",
];

export class RoleSelector extends PureComponent {
    onChange(e) {
        if (e.target.value === "nil") return;
        this.props.onChange(e);
    }

    render() {
        return (
            <select value={this.props.value} onChange={this.onChange.bind(this)}>
                <option key="nil" value="nil">{t("select")}</option>
                {ROLES.map(id =>
                    <option key={id} value={id}>{t.role(id)}</option>
                )}
            </select>
        );
    }

}

RoleSelector.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};

export class Role extends PureComponent {
    render() {
        if (!this.props.value) return <span></span>;
        const roleId = ROLES.find(id => id === this.props.value);
        const name = roleId ? t.role(roleId) : this.props.value;
        return (
            <span>
                {!roleId &&
                <ErrorModalButton tooltip={t("unknown_role")}>
                    <div>
                        <p>
                            {t("unknown_role")} <i>{name}</i>
                        </p>

                        <p>
                            {t("known_roles")}
                        </p>
                        <ul>
                            {ROLES.map(id => <li key={id} style={{fontStyle: "italic"}}>{id}</li>)}
                        </ul>
                    </div>
                </ErrorModalButton>}
                {name}
            </span>
        );
    }
}

Role.propTypes = {
    value: React.PropTypes.string.isRequired,
};
