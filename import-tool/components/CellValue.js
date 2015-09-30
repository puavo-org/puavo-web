
import React from "react";
import PureComponent from "./PureComponent";
import R from "ramda";
import {connect} from "react-redux";

import {onEnterKey} from "../utils";
import ColumnTypes, {ReactColumnType} from "../ColumnTypes";
import t from "../i18n";

import {Role, RoleSelector} from "./Role";
import {LegacyRole, LegacyRoleSelector} from "./LegacyRole";
import {UpdateType, UpdateTypeInput} from "./UpdateType";


export class CellValueInput extends PureComponent {

    componentDidMount() {
        if (this.refs.input) {
            const el = React.findDOMNode(this.refs.input);
            el.select();
        }
    }

    render() {
        const passProps = R.omit(["columnType", "onSelect"], this.props);

        switch(this.props.columnType.id) {
        case ColumnTypes.legacy_role.id:
            return <LegacyRoleSelector {...passProps} />;
        case ColumnTypes.role.id:
            return <RoleSelector {...passProps} />;
        case ColumnTypes.update_type.id:
            return <UpdateTypeInput {...passProps} />;
        default:
            return (
                <input
                    {...passProps}
                    ref="input"
                    onKeyUp={onEnterKey(this.props.onSelect)}
                    className="ColumnTypeSelector-default-value-input"
                    type="text"
                    placeholder={t("some_value")}
                />
            );
        }
    }
}


CellValueInput.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
    onSelect: React.PropTypes.func.isRequired,
    columnType: ReactColumnType.isRequired,
};

class Username extends PureComponent {
    render() {
        const {schoolId, username} = this.props;
        return (
            <a href={`/users/${schoolId}/username_redirect/${username}`}>{username}</a>
        );
    }
}
Username.propTypes = {
    username: React.PropTypes.string.isRequired,
    schoolId: React.PropTypes.number.isRequired,
};
Username = connect(state => ({schoolId: R.path(["defaultSchool", "id"], state)}))(Username);

export class CellValue extends PureComponent {
    render() {
        switch(this.props.columnType.id) {
        case ColumnTypes.username.id:
            return <Username username={this.props.value} />;
        case ColumnTypes.legacy_role.id:
            return <LegacyRole name={this.props.value} />;
        case ColumnTypes.role.id:
            return <Role value={this.props.value} />;
        case ColumnTypes.update_type.id:
            return <UpdateType value={this.props.value} />;
        default:
            return <span>{this.props.value}</span>;
        }
    }
}

CellValue.propTypes = {
    value: React.PropTypes.string.isRequired,
    columnType: ReactColumnType.isRequired,
};
