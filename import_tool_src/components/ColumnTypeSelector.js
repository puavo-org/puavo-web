
import React from "react";
import R from "ramda";
import {connect} from "react-redux";

import COLUMN_TYPES from "../column_types";
import {changeColumnType, changeColumnDefault} from "../actions";

class ColumnTypeSelector extends React.Component {

    constructor(props) {
        super(props);
        this.state = {defaultValue: this.props.currentDefaultValue};
    }


    setDefaultValue(e) {
        if (e.key !== "Enter") return;
        this.props.changeColumnDefault(this.props.columnIndex, this.state.defaultValue);
    }

    render() {
        return (
            <div className="ColumnTypeSelector">
                <select
                    value={this.props.currentTypeId}
                    onChange={e => this.props.changeColumnType(this.props.columnIndex, e.target.value)}>
                    {R.values(COLUMN_TYPES).map(columnType => {
                        return <option value={columnType.id}>{columnType.name}</option>;
                    })}
                </select>
                <input
                    type="text"
                    value={this.state.defaultValue}
                    onChange={e => this.setState({defaultValue: e.target.value})}
                    onKeyUp={this.setDefaultValue.bind(this)}
                />
            </div>
        );
    }

}


ColumnTypeSelector.propTypes = {
    changeColumnDefault: React.PropTypes.func.isRequired,
    changeColumnType: React.PropTypes.func.isRequired,
    columnIndex: React.PropTypes.number.isRequired,
    currentTypeId: React.PropTypes.string,
    currentDefaultValue: React.PropTypes.string,
};

function selectProps(state, {columnIndex}) {
    return {
        columnIndex,
        currentDefaultValue: R.path(["importData", "defaultValues", columnIndex], state),
        currentTypeId: R.path(["importData", "columns", columnIndex, "id"], state),
    };
}

export default connect(selectProps, {changeColumnType, changeColumnDefault})(ColumnTypeSelector);
