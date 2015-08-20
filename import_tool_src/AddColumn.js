
import React from "react";
import {connect} from "react-redux";
import R from "ramda";

import COLUMN_TYPES from "./column_types";
import {addColumn} from "./actions";

class AddColumn extends React.Component {

    constructor(props) {
        super(props);
        this.state = {};
    }

    addColumn() {
        this.props.dispatch(addColumn(this.state.value));
    }

    render() {
        return (
            <div className="AddColumn">
                <select value={this.state.value} onChange={e => this.setState({value: e.target.value})}>
                    {R.toPairs(COLUMN_TYPES).map(([columnType, column]) => {
                        return <option value={columnType}>{column.name}</option>;
                    })}
                </select>
                <button disabled={!this.state.value} onClick={this.addColumn.bind(this)}>Add</button>
            </div>
        );
    }

}

AddColumn.propTypes = {
    dispatch: React.PropTypes.func.isRequired,
};

export default connect()(AddColumn);

