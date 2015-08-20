
import React from "react";
import {connect} from "react-redux";

import {setCustomValue} from "../actions";
import {getCellValue} from "../utils";

class Cell extends React.Component {

    constructor(props) {
        super(props);
        this.state = {
            customValue: getCellValue(props.value),
            editing: false,
        };
    }

    setCustomValue(e) {
        if (e.key !== "Enter") return;
        if (this.state.customValue !== getCellValue(this.props.value)) {
            this.props.setCustomValue(this.props.rowIndex, this.props.columnIndex, this.state.customValue);
        }
        this.setState({editing: false});
    }

    changeCustomValue(e) {
        this.setState({customValue: e.target.value});
    }

    startEdit(e) {
        if (e) e.preventDefault();
        this.setState({editing: true});
    }

    render() {
        return (
            <div>

                <pre>{JSON.stringify(this.props.value)}</pre>
                {!this.state.editing &&
                    <a href="#" onClick={this.startEdit.bind(this)}>m</a>}

                {this.state.editing &&
                <input type="text"
                    value={this.state.customValue}
                    onChange={this.changeCustomValue.bind(this)}
                    onKeyUp={this.setCustomValue.bind(this)} />
                }

            </div>
        );
    }
}

Cell.propTypes = {
    columnIndex: React.PropTypes.number.isRequired,
    rowIndex: React.PropTypes.number.isRequired,
    setCustomValue: React.PropTypes.func.isRequired,
    value: React.PropTypes.object.isRequired,
};

export default connect(null, {setCustomValue})(Cell);
