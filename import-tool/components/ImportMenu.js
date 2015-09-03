
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";
import R from "ramda";
import {Overlay} from "react-overlays";

import ArrowBox from "./ArrowBox";
import Fa from "./Fa";
import ColumnTypes from "../ColumnTypes";
import {addColumn} from "../actions";
import {preventDefault} from "../utils";
import {resetState} from "../StateStorage";
import ConfirmationButton from "./ConfirmationButton";

class ImportMenu extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            showMenu: false,
        };
    }

    addColumn(e) {
        if (e && e.target.value !== "nil") {
            this.props.addColumn(e.target.value);
            this.hideMenu();
        }
    }

    showMenu() {
        this.setState({showMenu: true});
    }

    hideMenu() {
        this.setState({showMenu: false});
    }

    render() {
        return (
            <div className="ImportMenu">

                <button className="pure-button"
                    ref="target"
                    onClick={preventDefault(this.showMenu.bind(this))}>
                    <Fa icon="bars" />
                </button>

                <Overlay
                    show={this.state.showMenu}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => React.findDOMNode(this.refs.target)}
                >
                    <ArrowBox>
                        <form className="pure-form">
                            <fieldset>
                                <legend>Add column</legend>
                                <select onChange={this.addColumn.bind(this)} ref="select">
                                    <option key="nil" value="nil" >Select...</option>
                                    {R.toPairs(ColumnTypes).map(([columnType, column]) => {
                                        return <option key={columnType} value={columnType}>{column.name}</option>;
                                    })}
                                </select>
                            </fieldset>

                            <ConfirmationButton
                                className="pure-button danger"
                                style={{width: "100%", marginTop: 25}}
                                onClick={preventDefault(this.props.resetState)}
                            >New import</ConfirmationButton>

                        </form>
                    </ArrowBox>
                </Overlay>
            </div>
        );
    }

}

ImportMenu.propTypes = {
    addColumn: React.PropTypes.func.isRequired,
    resetState: React.PropTypes.func.isRequired,
};

export default connect(null, {addColumn, resetState})(ImportMenu);

