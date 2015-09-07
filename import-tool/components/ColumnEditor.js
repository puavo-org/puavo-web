
import React from "react";
import PureComponent from "react-pure-render/component";
import R from "ramda";
import {connect} from "react-redux";
import {Overlay} from "react-overlays";

import Fa from "./Fa";
import ArrowBox from "./ArrowBox";
import ColumnTypes from "../ColumnTypes";
import {changeColumnType, fillColumn, dropColumn} from "../actions";
import {onEnterKey, preventDefault} from "../utils";

class ColumnEditor extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            fillValue: "",
            override: false,
            showMenu: false,
        };
    }


    fillColumn() {
        this.props.fillColumn(this.props.columnIndex, this.state.fillValue, this.state.override);
        this.hideMenu();
    }

    showMenu() {
        this.setState({showMenu: true});
    }

    hideMenu() {
        this.setState({showMenu: false});
    }

    changeColumnType(value) {
        this.props.changeColumnType(this.props.columnIndex, value);
        this.hideMenu();
    }

    dropColumn() {
        this.props.dropColumn(this.props.columnIndex);
        this.hideMenu();
    }

    render() {
        return (
            <span className="ColumnEditor">

                <a href="#" ref="target" style={{float: "right"}} onClick={preventDefault(this.showMenu.bind(this))}>
                    <Fa icon="pencil" />
                </a>

                <Overlay
                    show={this.state.showMenu}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => React.findDOMNode(this.refs.target)}
                >
                    <ArrowBox>
                        <form className="pure-form pure-form-stacked">
                            <fieldset>
                                <legend>Change type</legend>
                                <select
                                    value={this.props.currentTypeId}
                                    onChange={e => this.changeColumnType(e.target.value)}>
                                    {R.values(ColumnTypes).map(columnType => {
                                        return <option key={columnType.id} value={columnType.id}>{columnType.name}</option>;
                                    })}
                                </select>

                                <legend>Fill</legend>

                                <input
                                    className="ColumnTypeSelector-default-value-input"
                                    type="text"
                                    placeholder="Default"
                                    value={this.state.fillValue}
                                    onChange={e => this.setState({fillValue: e.target.value})}
                                    onKeyUp={onEnterKey(this.fillColumn.bind(this))}
                                />

                                <label style={{fontSize: "small"}}>
                                    <input
                                        type="checkbox"
                                        checked={this.state.override}
                                        onChange={_ => this.setState({override: !this.state.override})} />
                                    Override existing values
                                </label>

                                <button
                                    style={{width: "100%"}}
                                    className="pure-button"
                                    onClick={preventDefault(this.fillColumn.bind(this))}
                                >Fill</button>

                                <div style={{marginTop: 50}} />

                                <button className="pure-button danger"
                                    onClick={preventDefault(this.dropColumn.bind(this))}
                                    >
                                    <Fa icon="trash-o" /> Remove column
                                </button>

                            </fieldset>
                        </form>
                    </ArrowBox>
                </Overlay>
            </span>
        );
    }

}


ColumnEditor.propTypes = {
    fillColumn: React.PropTypes.func.isRequired,
    dropColumn: React.PropTypes.func.isRequired,
    changeColumnType: React.PropTypes.func.isRequired,
    columnIndex: React.PropTypes.number.isRequired,
    currentTypeId: React.PropTypes.string,
};

export default connect(null, {changeColumnType, fillColumn, dropColumn})(ColumnEditor);
