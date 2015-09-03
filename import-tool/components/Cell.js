
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";
import {Overlay} from "react-overlays";

import ArrowBox from "./ArrowBox";
import Modal from "./Modal";
import Fa from "./Fa";
import {setCustomValue} from "../actions";
import {onEnterKey, preventDefault} from "../utils";

class Cell extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            customValue: props.value,
            showError: false,
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

    componentDidUpdate(__, prevState) {
        if (this.state.editing && !prevState.editing) {
            const el = React.findDOMNode(this.refs.input);
            el.select();
        }
    }

    showMenu() {
        this.setState({editing: true});
    }

    hideMenu() {
        this.setState({editing: false});
    }

    render() {
        return (
            <div className="Cell">

                <div>
                    {this.props.validationErrors.length > 0 &&
                    <span>
                        <a href="#" onClick={preventDefault(_ => this.setState({showError: true}))}>
                            <Fa icon="exclamation-triangle" className="error" />
                        </a>
                        {" "}
                    </span>}

                    {this.props.value}

                    <span className="Cell-edit-buttons">
                        {" "}
                        <a href="#" onClick={preventDefault(this.revertToOriginal.bind(this))}>
                            <Fa icon="recycle" />
                        </a>
                        {" "}
                        <a href="#" ref="editButton" onClick={preventDefault(this.showMenu.bind(this))}>
                            <Fa icon="pencil" />
                        </a>
                    </span>
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
                            <input type="text"
                                ref="input"
                                value={this.state.customValue}
                                onChange={this.changeCustomValue.bind(this)}
                                onKeyUp={onEnterKey(this.setCustomValue.bind(this))}
                            />
                            <button
                                className="pure-button pure-button-primary"
                                style={{width: "100%"}}
                                onClick={preventDefault(this.setCustomValue.bind(this))}>ok</button>
                        </form>
                    </ArrowBox>
                </Overlay>



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
    value: React.PropTypes.string.isRequired,
    validationErrors: React.PropTypes.array,
};

Cell.defaultProps = {
    validationErrors: [],
};

export default connect(null, {setCustomValue})(Cell);
