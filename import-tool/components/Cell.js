
import R from "ramda";
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";

import Modal from "./Modal";
import Fa from "./Fa";
import {setCustomValue} from "../actions";
import {getCellValue, didPressEnter, preventDefault} from "../utils";

class Cell extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            customValue: getCellValue(props.value),
            showError: false,
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

    revertToOriginal() {
        this.setState({customValue: ""});
        this.props.setCustomValue(this.props.rowIndex, this.props.columnIndex, "");
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
                    {this.props.validationErrors.length > 0 &&
                    <span>
                        <a href="#" onClick={preventDefault(_ => this.setState({showError: true}))}>
                            <Fa icon="exclamation-triangle" className="error" />
                        </a>
                        {" "}
                    </span>}

                    {getCellValue(this.props.value)}

                    {" "}
                    <span className="Cell-edit-buttons">
                        <a href="#" onClick={preventDefault(this.startEdit.bind(this))}>
                            <Fa icon="pencil" />
                        </a>
                        {" "}
                        <a href="#" onClick={preventDefault(this.revertToOriginal.bind(this))}>
                            <Fa icon="recycle" />
                        </a>
                    </span>
                </div>}

                {this.state.editing &&
                <span>
                    <form className="pure-form">
                        <input type="text"
                            ref="input"
                            value={this.state.customValue}
                            onChange={this.changeCustomValue.bind(this)}
                            onKeyUp={R.both(didPressEnter, this.setCustomValue.bind(this))}
                        />
                        <button
                            className="pure-button"
                            onClick={preventDefault(this.setCustomValue.bind(this))}>ok</button>
                    </form>
                </span>}



                {this.state.showError &&
                    <Modal show onHide={e => this.setState({showError: false})}>
                        <div>
                            <h1>Error</h1>

                            <pre style={{fontSize: "small"}}>
                                {JSON.stringify(this.props.validationErrors, null, "  ")}
                            </pre>

                        </div>
                    </Modal>
                }

            </div>
        );
    }
}

Cell.propTypes = {
    columnIndex: React.PropTypes.number.isRequired,
    rowIndex: React.PropTypes.number.isRequired,
    setCustomValue: React.PropTypes.func.isRequired,
    value: React.PropTypes.object,
    columnType: React.PropTypes.object,
    validationErrors: React.PropTypes.array,
};

Cell.defaultProps = {
    validationErrors: [],
};

function select(state, {rowIndex, columnIndex}) {
    const {rowStatus, importData: {rows, columns}} = state;
    const columnType = columns[columnIndex];

    return {
        rowIndex,
        columnIndex,
        columnType,
        value: R.path([rowIndex, columnIndex], rows),
        validationErrors: R.path([
            rowIndex,
            "attributeErrors",
            columnType.attribute,
        ], rowStatus),
    };
}

export default connect(select, {setCustomValue})(Cell);
