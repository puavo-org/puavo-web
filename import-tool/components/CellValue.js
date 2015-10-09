
import React from "react";
import PureComponent from "./PureComponent";

import {onEnterKey} from "../utils";
import ColumnTypes, {ReactColumnType} from "../ColumnTypes";
import t from "../i18n";

import {Role, RoleSelector} from "./Role";
import {LegacyRole, LegacyRoleSelector} from "./LegacyRole";
import {UpdateType, UpdateTypeInput} from "./UpdateType";
import {Username, UsernameInput} from "./Username";


export class CellValueInput extends PureComponent {

    componentDidMount() {
        if (this.refs.input) {
            this.refs.input.select();
        }
    }

    render() {
        const {columnType, onSelect, ...passProps} = this.props;

        switch(columnType.id) {
        case ColumnTypes.username.id:
            return <UsernameInput {...passProps} />;
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
                    onKeyUp={onEnterKey(onSelect)}
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
