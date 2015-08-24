
import R from "ramda";
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";

import {setCustomValue} from "../actions";
import {getCellValue, didPressEnter} from "../utils";

class Cell extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            customValue: getCellValue(props.value),
            editing: false,
        };
    }

    componentWillReceiveProps(nextProps) {
        this.setState({customValue: getCellValue(nextProps.value)});
    }

    setCustomValue() {
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

    componentDidUpdate(__, prevState) {
        if (this.state.editing && !prevState.editing) {
            const el = React.findDOMNode(this.refs.input);
            el.select();
        }
    }

    render() {
        return (
            <div className="Cell">

                {!this.state.editing &&
                <div>
                    {getCellValue(this.props.value)}
                    {" "}
                    <a href="#" onClick={this.startEdit.bind(this)}>e</a>
                </div>}

                {this.state.editing &&
                <span>
                    <input type="text"
                        ref="input"
                        value={this.state.customValue}
                        onChange={this.changeCustomValue.bind(this)}
                        onKeyUp={R.both(didPressEnter, this.setCustomValue.bind(this))}
                    />
                    <button onClick={this.setCustomValue.bind(this)}>ok</button>
                </span>}

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
