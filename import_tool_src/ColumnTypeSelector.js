
import React from "react";
import R from "ramda";

import COLUMN_TYPES from "./column_types";

export default class ColumnTypeSelector extends React.Component {

    render() {
        return (
            <select value={this.props.value} onChange={this.props.onChange}>
                {R.values(COLUMN_TYPES).map(columnType => {
                    return <option value={columnType.attribute}>{columnType.name}</option>;
                })}
            </select>
        );
    }

}


ColumnTypeSelector.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};
