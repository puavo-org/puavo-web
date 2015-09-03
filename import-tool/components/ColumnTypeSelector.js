
import React from "react";
import PureComponent from "react-pure-render/component";
import R from "ramda";
import {connect} from "react-redux";
import {Overlay} from "react-overlays";

import Fa from "./Fa";
import ToolTip from "./ToolTip";
import COLUMN_TYPES from "../column_types";
import {changeColumnType, setDefaultValue, dropColumn} from "../actions";
import {onEnterKey, preventDefault} from "../utils";

class ColumnTypeSelector extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            defaultValue: this.props.currentDefaultValue,
            showMenu: false,
        };
    }


    setDefaultValue() {
        this.props.setDefaultValue(this.props.columnIndex, this.state.defaultValue);
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
    }

    render() {
        return (
            <span className="ColumnTypeSelector">

                <a href="#" ref="target" onClick={preventDefault(this.showMenu.bind(this))}>
                    <Fa icon="edit" />
                </a>

                <Overlay
                    show={this.state.showMenu}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => React.findDOMNode(this.refs.target)}
                >
                    <ToolTip>
                        <form className="pure-form pure-form-stacked">
                            <fieldset>
                                <legend>Change type</legend>
                                <select
                                    value={this.props.currentTypeId}
                                    onChange={e => this.changeColumnType(e.target.value)}>
                                    {R.values(COLUMN_TYPES).map(columnType => {
                                        return <option key={columnType.id} value={columnType.id}>{columnType.name}</option>;
                                    })}
                                </select>

                                <legend>Fill empty values</legend>
                                <input
                                    className="ColumnTypeSelector-default-value-input"
                                    type="text"
                                    placeholder="Default"
                                    value={this.state.defaultValue}
                                    onChange={e => this.setState({defaultValue: e.target.value})}
                                    onKeyUp={onEnterKey(this.setDefaultValue.bind(this))}
                                />

                                <button
                                    style={{width: "100%"}}
                                    className="pure-button"
                                    onClick={preventDefault(this.setDefaultValue.bind(this))}
                                >Fill</button>

                                <div style={{marginTop: 50}} />

                                <button className="pure-button danger"
                                    onClick={preventDefault(this.dropColumn.bind(this))}
                                    >
                                    <Fa icon="trash-o" /> Remove column
                                </button>

                            </fieldset>
                        </form>
                    </ToolTip>
                </Overlay>
            </span>
        );
    }

}


ColumnTypeSelector.propTypes = {
    setDefaultValue: React.PropTypes.func.isRequired,
    dropColumn: React.PropTypes.func.isRequired,
    changeColumnType: React.PropTypes.func.isRequired,
    columnIndex: React.PropTypes.number.isRequired,
    currentTypeId: React.PropTypes.string,
    currentDefaultValue: React.PropTypes.string,
};

function selectProps(state, {columnIndex}) {
    return {
        columnIndex,
        currentDefaultValue: R.path(["importData", "defaultValues", columnIndex], state),
        currentTypeId: R.path(["importData", "columns", columnIndex, "id"], state),
    };
}

export default connect(selectProps, {changeColumnType, setDefaultValue, dropColumn})(ColumnTypeSelector);
