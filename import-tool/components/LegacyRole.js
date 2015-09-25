
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";

import t from "../i18n";

import ErrorModalButton from "./ErrorModalButton";

class LegacyRoleSelector extends PureComponent {

    onChange(e) {
        if (e.target.value === "nil") return;
        this.props.onChange(e);
    }

    render() {
        return (
            <select value={this.props.value} onChange={this.onChange.bind(this)}>
                <option key="nil" value="nil">Select...</option>
                {this.props.legacyRoles.map(role =>
                    <option key={role.id} value={role.name}>{role.name}</option>
                )}
            </select>
        );
    }
}
LegacyRoleSelector.propTypes = {
    legacyRoles: React.PropTypes.array.isRequired,
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};
LegacyRoleSelector = connect(({legacyRoles}) => ({legacyRoles}))(LegacyRoleSelector);


class LegacyRole extends PureComponent {
    render() {
        return (
            <span>
                {this.props.unknown &&
                <ErrorModalButton tooltip={t("unknown_legacy_role")}>
                    <p>
                        {t("unknown_legacy_role")} <span style={{fontStyle: "italic"}}>{this.props.name}</span>
                    </p>
                    <p>
                        {t("known_legacy_roles")}
                    </p>
                    <ul>
                        {this.props.legacyRoles.map(r => <li key={r.id} style={{fontStyle: "italic"}}>{r.name}</li>)}
                    </ul>
                </ErrorModalButton>}
                {this.props.name}
            </span>
        );
    }
}
LegacyRole.propTypes = {
    name: React.PropTypes.string.isRequired,
    unknown: React.PropTypes.bool.isRequired,
    legacyRoles: React.PropTypes.array.isRequired,
};
LegacyRole = connect(({legacyRoles}, {name}) => {
    return {
        legacyRoles,
        name,
        unknown: !!(name && !legacyRoles.some(r => r.name === name)),
    };
})(LegacyRole);


export {LegacyRoleSelector, LegacyRole};
