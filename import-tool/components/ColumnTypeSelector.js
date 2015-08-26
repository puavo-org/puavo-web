
import React from "react";
import PureComponent from "react-pure-render/component";
import R from "ramda";
import {connect} from "react-redux";

import COLUMN_TYPES from "../column_types";
import {changeColumnType, setDefaultValue} from "../actions";
import {didPressEnter} from "../utils";

class ColumnTypeSelector extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {defaultValue: this.props.currentDefaultValue};
    }


    setDefaultValue() {
        this.props.setDefaultValue(this.props.columnIndex, this.state.defaultValue);
    }

    render() {
        return (
            <div className="ColumnTypeSelector">
                <select
                    value={this.props.currentTypeId}
                    onChange={e => this.props.changeColumnType(this.props.columnIndex, e.target.value)}>
                    {R.values(COLUMN_TYPES).map(columnType => {
                        return <option key={columnType.id} value={columnType.id}>{columnType.name}</option>;
                    })}
                </select>
                <br />
                <input
                    className="ColumnTypeSelector-default-value-input"
                    type="text"
                    placeholder="Default"
                    value={this.state.defaultValue}
                    onChange={e => this.setState({defaultValue: e.target.value})}
                    onKeyUp={R.both(didPressEnter, this.setDefaultValue.bind(this))}
                />
                <button onClick={this.setDefaultValue.bind(this)}>ok</button>
            </div>
        );
    }

}


ColumnTypeSelector.propTypes = {
    setDefaultValue: React.PropTypes.func.isRequired,
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

export default connect(selectProps, {changeColumnType, setDefaultValue})(ColumnTypeSelector);
