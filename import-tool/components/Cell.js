
import React from "react";
import R from "ramda";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";
import {Overlay} from "react-overlays";

import {setCustomValue} from "../actions";
import {preventDefault} from "../utils";
import {ReactColumnType} from "../ColumnTypes";

import ArrowBox from "./ArrowBox";
import {CellValueInput, CellValue} from "./CellValue";
import Fa from "./Fa";
import Modal from "./Modal";

class Cell extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            customValue: props.value,
            showErrorModal: false,
            editing: false,
        };
    }

    componentWillReceiveProps(nextProps) {
        this.setState({customValue: nextProps.value});
    }

    setCustomValue() {
        if (this.state.customValue !== this.props.value) {
            this.props.setCustomValue(this.props.rowIndex, this.props.columnIndex, this.state.customValue);
        }
        this.hideMenu();
    }

    revertToOriginal() {
        this.setState({customValue: ""});
        this.props.setCustomValue(this.props.rowIndex, this.props.columnIndex, "");
    }

    changeCustomValue(e) {
        this.setState({customValue: e.target.value});
    }

    showMenu() {
        this.setState({editing: true});
    }

    hideMenu() {
        this.setState({editing: false});
    }

    hasValidationErrors() {
        return this.props.validationErrors.length > 0;
    }

    missingRequiredValue() {
        return !this.props.value && this.props.required;
    }

    hasErrors() {
        return this.hasValidationErrors() || this.missingRequiredValue();
    }

    render() {
        return (
            <div className="Cell" style={{whiteSpace: "nowrap"}}>

                <div>
                    {this.hasErrors() &&
                    <span>
                        <a href="#" onClick={preventDefault(_ => this.setState({showErrorModal: true}))}>
                            <Fa icon="exclamation-triangle" className="error" />
                        </a>
                        {" "}
                    </span>}

                    {this.state.showErrorModal &&
                    <Modal show onHide={e => this.setState({showErrorModal: false})}>
                        <div>
                            <h1>Error</h1>

                            {this.missingRequiredValue() &&
                            <div>
                                Value is missing
                            </div>}

                            {this.hasValidationErrors() &&
                            <pre style={{fontSize: "small"}}>
                                {JSON.stringify(this.props.validationErrors, null, "  ")}
                            </pre>}

                        </div>
                    </Modal>}


                    <CellValue columnType={this.props.columnType} value={this.props.value} />

                    {this.props.status !== "ok" &&
                    <span style={{float: "right"}}>
                        {" "}
                        <a href="#" onClick={preventDefault(this.revertToOriginal.bind(this))}>
                            <Fa icon="recycle" />
                        </a>
                        {" "}
                        <a href="#" ref="editButton" onClick={preventDefault(this.showMenu.bind(this))}>
                            <Fa icon="pencil" />
                        </a>
                    </span>}
                </div>

                <Overlay
                    show={this.state.editing}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => React.findDOMNode(this.refs.editButton)}
                >
                    <ArrowBox>
                        <form className="pure-form">
                            <CellValueInput
                                columnType={this.props.columnType}
                                value={this.state.customValue}
                                onChange={this.changeCustomValue.bind(this)}
                                onSelect={this.setCustomValue.bind(this)}
                            />

                            <button
                                className="pure-button pure-button-primary"
                                style={{width: "100%"}}
                                onClick={preventDefault(this.setCustomValue.bind(this))}>ok</button>
                        </form>
                    </ArrowBox>
                </Overlay>
            </div>
        );
    }
}

Cell.propTypes = {
    columnIndex: React.PropTypes.number.isRequired,
    rowIndex: React.PropTypes.number.isRequired,
    setCustomValue: React.PropTypes.func.isRequired,
    value: React.PropTypes.string.isRequired,
    status: React.PropTypes.string.isRequired,
    validationErrors: React.PropTypes.array,
    required: React.PropTypes.bool,
    columnType: ReactColumnType.isRequired,
};

Cell.defaultProps = {
    validationErrors: [],
};

function select(state, parentProps) {
    return {
        status: R.path(["rowStatus", parentProps.rowIndex, "status"], state) || "waiting",
    };
}

export default connect(select, {setCustomValue})(Cell);
