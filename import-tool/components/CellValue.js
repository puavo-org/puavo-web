
import React from "react";
import PureComponent from "./PureComponent";

import {onEnterKey} from "../utils";
import {AllColumnTypes, ReactColumnType} from "../ColumnTypes";
import t from "../i18n";

import {Role, RoleSelector} from "./Role";
import {LegacyRole, LegacyRoleSelector} from "./LegacyRole";
import {UpdateType, UpdateTypeInput} from "./UpdateType";
import {Username, UsernameInput} from "./Username";
import {Group, GroupSelector} from "./Group";


export class CellValueInput extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {changed: false};
    }

    componentDidMount() {
        if (this.refs.input) {
            this.refs.input.select();
        }
    }

    onChange(e) {
        this.setState({changed: true});
        this.props.onChange(e);
    }

    render() {
        const {
            columnType,
            onSelect,
            onChange,
            initialValue,
            value,
            ...otherProps,
        } = this.props;

        const passProps = {
            ...otherProps,
            value: !value && !this.state.changed ? initialValue : value,
            onChange: this.onChange.bind(this),
        };

        switch(columnType.id) {
        case AllColumnTypes.username.id:
            return <UsernameInput {...passProps} />;
        case AllColumnTypes.legacy_role.id:
            return <LegacyRoleSelector {...passProps} />;
        case AllColumnTypes.group.id:
            return <GroupSelector {...passProps} />;
        case AllColumnTypes.role.id:
            return <RoleSelector {...passProps} />;
        case AllColumnTypes.update_type.id:
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
    initialValue: React.PropTypes.string,
};


export class CellValue extends PureComponent {
    render() {
        switch(this.props.columnType.id) {
        case AllColumnTypes.username.id:
            return <Username username={this.props.value} />;
        case AllColumnTypes.legacy_role.id:
            return <LegacyRole name={this.props.value} />;
        case AllColumnTypes.group.id:
            return <Group abbreviation={this.props.value} />;
        case AllColumnTypes.role.id:
            return <Role value={this.props.value} />;
        case AllColumnTypes.update_type.id:
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
