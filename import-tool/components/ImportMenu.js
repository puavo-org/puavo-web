
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";
import R from "ramda";
import {Overlay} from "react-overlays";

import {addColumn} from "../actions";
import ColumnTypes from "../ColumnTypes";
import {preventDefault} from "../utils";
import {resetState} from "../StateStorage";
import t from "../i18n";

import ArrowBox from "./ArrowBox";
import ConfirmationButton from "./ConfirmationButton";
import Fa from "./Fa";

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
                                <legend>{t("add_column")}</legend>
                                <select onChange={this.addColumn.bind(this)} ref="select">
                                    <option key="nil" value="nil" >{t("select")}</option>
                                    {R.toPairs(ColumnTypes).map(([columnType, column]) => {
                                        return <option key={columnType} value={columnType}>{t.type(column.id)}</option>;
                                    })}
                                </select>
                            </fieldset>

                            <ConfirmationButton
                                className="pure-button danger"
                                style={{width: "100%", marginTop: 25}}
                                onClick={preventDefault(_ => {
                                    this.props.resetState();
                                    setTimeout(() => window.location.reload(), 1);
                                })}
                            >{t("start_new_import")}</ConfirmationButton>

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

