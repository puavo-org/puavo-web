
import React from "react";
import PureComponent from "./PureComponent";
import R from "ramda";
import {connect} from "react-redux";
import {Overlay} from "react-overlays";

import {changeColumnType, fillColumn, dropColumn, clearAutoOpenColumnEditor} from "../actions";
import {ReactColumnType} from "../ColumnTypes";
import {preventDefault} from "../utils";
import t from "../i18n";

import ArrowBox from "./ArrowBox";
import {CellValueInput} from "./CellValue";
import Icon from "./Icon";

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

    componentWillMount() {
        if (this.props.autoOpenColumnEditor === this.props.columnIndex) {
            this.showMenu();
            this.props.clearAutoOpenColumnEditor();
        }
    }

    hideMenu() {
        this.setState({showMenu: false});
    }

    changeColumnType(value) {
        this.props.changeColumnType(this.props.columnIndex, value);
    }

    dropColumn() {
        this.props.dropColumn(this.props.columnIndex);
        this.hideMenu();
    }

    render() {
        return (
            <span className="ColumnEditor">

                <a href="#" ref="target" style={{float: "right"}} onClick={preventDefault(this.showMenu.bind(this))}>
                    <Icon icon="pencil" />
                </a>

                <Overlay
                    show={this.state.showMenu}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => this.refs.target}
                >
                    <ArrowBox>
                        <form className="pure-form pure-form-stacked">
                            <fieldset>
                                <legend>{t("change_type")}</legend>
                                <select
                                    value={this.props.columnType.id}
                                    onChange={e => this.changeColumnType(e.target.value)}>
                                    {R.values(this.props.activeColumnTypes).map(columnType => {
                                        return <option key={columnType.id} value={columnType.id}>{t.type(columnType.id)}</option>;
                                    })}
                                </select>


                                <legend>{t("fill_values")}</legend>

                                <CellValueInput
                                    columnType={this.props.columnType}
                                    value={this.state.fillValue}
                                    onChange={e => this.setState({fillValue: e.target.value})}
                                    onSelect={this.fillColumn.bind(this)}
                                />

                                <button
                                    style={{width: "100%"}}
                                    className="pure-button"
                                    onClick={preventDefault(this.fillColumn.bind(this))}
                                >{t("fill")}</button>

                                <label style={{fontSize: "small"}}>
                                    <input
                                        type="checkbox"
                                        checked={this.state.override}
                                        onChange={_ => this.setState({override: !this.state.override})} />
                                    {t("override_existing_values")}
                                </label>


                                <legend>{t("remove_column")}</legend>
                                <button className="pure-button danger"
                                    onClick={preventDefault(this.dropColumn.bind(this))}
                                    >
                                    <Icon icon="trash" />
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
    clearAutoOpenColumnEditor: React.PropTypes.func.isRequired,
    changeColumnType: React.PropTypes.func.isRequired,
    columnIndex: React.PropTypes.number.isRequired,
    columnType: ReactColumnType.isRequired,
    autoOpenColumnEditor: React.PropTypes.number,
    activeColumnTypes: React.PropTypes.object.isRequired,
};

export default connect(
    R.pick(["autoOpenColumnEditor", "activeColumnTypes"]),
    {changeColumnType, fillColumn, dropColumn, clearAutoOpenColumnEditor}
)(ColumnEditor);
