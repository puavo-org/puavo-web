
import R from "ramda";
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";

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
                    <option key={role.id} value={role.id}>{role.name}</option>
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
        return <span>{this.props.name}</span>;
    }
}
LegacyRole.propTypes = {
    id: React.PropTypes.string.isRequired,
    name: React.PropTypes.string.isRequired,
};
LegacyRole = connect(({legacyRoles}, parentProps) => {
    if (!parentProps.id) return {name: ""};
    const name = R.find(R.propEq("id", parentProps.id))(legacyRoles).name;
    return {name};
})(LegacyRole);


export {LegacyRoleSelector, LegacyRole};
