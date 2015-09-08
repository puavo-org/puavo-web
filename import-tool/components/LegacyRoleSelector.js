
import React from "react";
import PureComponent from "react-pure-render/component";
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

export default connect(({legacyRoles}) => ({legacyRoles}))(LegacyRoleSelector);
