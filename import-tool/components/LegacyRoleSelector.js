
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";

class LegacyRoleSelector extends PureComponent {
    render() {
        return (
            <select value={this.props.value} onChange={this.props.onChange}>
                <option key="nil" value={null}>Select...</option>
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
