
import React from "react";
import R from "ramda";
import {connect} from "react-redux";
import PureComponent from "./PureComponent";
import Modal from "./Modal";

import t from "../i18n";
import {AllColumnTypes, pickRequiredColumns} from "../ColumnTypes";
import {parseImportString, startImport, dropRow, createPasswordResetIntentForNewUsers} from "../actions";
import {getCellValue, preventDefault, deepFreeze} from "../utils";

import DataPicker from "./DataPicker";
import Cell from "./Cell";
import ImportMenu from "./ImportMenu";
import ColumnEditor from "./ColumnEditor";
import StatusIcon from "./StatusIcon";
import Icon from "./Icon";


const isRequired = R.propEq("required", true);

function hasValuesInRequiredCells(columns, rows) {
    return rows.every(row => {
        return columns.every((column, i) => {
            if (!isRequired(column)) return true;
            return !!getCellValue(row[i]);
        });
    });
}

const areAllRowsOk = R.compose(
   R.both(
       // no rows not ok
       R.compose(R.not, R.isEmpty),
       // every status must be ok
       R.all(R.propEq("status", "ok"))
    ),
    R.values
);

const defaultErrors = deepFreeze([]);

class ImportTool extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {showModalFor: null};
    }

    startImport() {
        this.props.startImport();
    }

    render() {
        const {columns, rows, rowStatus} = this.props;
        const missingColumns = this.props.findMissingRequiredColumns(columns);

        return (
            <div className="ImportTool">
                {rows.length == 0 && <DataPicker />}

                {this.state.showModalFor !== null &&
                <Modal show onHide={e => this.setState({showModalFor: null})}>
                    <div style={{width: 800}}>
                        <h2>Errors</h2>
                        <p>
                            TODO: Should make this more readable
                        </p>
                        <pre>
                            {JSON.stringify(rowStatus[this.state.showModalFor], null, "  ")}
                        </pre>
                    </div>
                </Modal>}

                {rows.length > 0 &&
                <div>
                    <div className="ImportTool-editor" style={{overflow: "auto", overflowY: "hidden"}}>
                        <table className="pure-table pure-table-striped" style={{width: "100%", overflow: "auto"}}>
                            <thead>
                                <tr>
                                    <th key="status">
                                        {t("status")}
                                    </th>

                                    {columns.map((columnType, columnIndex) => {
                                        return (
                                            <th key={columnIndex}>
                                                {t.type(columnType.id)}{" "}
                                                <ColumnEditor
                                                    columnType={columnType}
                                                    columnIndex={columnIndex}
                                                    currentTypeId={R.compose(
                                                        R.defaultTo(AllColumnTypes.unknown.id),
                                                        R.path([columnIndex, "id"])
                                                    )(columns)}
                                                />
                                            </th>
                                        );
                                    })}
                                    <th style={{textAlign: "right"}}>
                                        <ImportMenu />
                                    </th>
                                </tr>
                            </thead>
                            <tbody>
                                {rows.map((row, rowIndex) => {
                                    const rowStatusString = R.path([rowIndex, "status"], rowStatus) || "waiting";
                                    const created = !!R.path([rowIndex, "created"], rowStatus);
                                    const userUpdated = !!R.path([rowIndex, "userUpdated"], rowStatus);


                                    var statusIcon = <StatusIcon status={rowStatusString} />;

                                    if (rowStatusString === "error") {
                                        statusIcon = (
                                            <a href="#" onClick={preventDefault(_ => this.setState({showModalFor: rowIndex}))}>
                                                {statusIcon} Virhe
                                            </a>
                                        );
                                    }

                                    return (
                                        <tr key={rowIndex}>
                                            <td>
                                                {statusIcon}
                                                {created && <span> {t("created")}</span>}
                                                {userUpdated && <span> {t("user_updated")}</span>}
                                            </td>

                                            {columns.map((columnType, columnIndex) => {
                                                let validationErrors = defaultErrors;
                                                if (rowStatusString === "error") {
                                                    validationErrors = R.path([
                                                        rowIndex,
                                                        "attributeErrors",
                                                        columnType.attribute,
                                                    ], rowStatus);
                                                }

                                                const {customValue="", originalValue=""} = R.path([rowIndex, columnIndex], rows) || {};

                                                return (
                                                    <td key={columnIndex}>
                                                        <Cell
                                                            rowIndex={rowIndex}
                                                            required={columnType.required}
                                                            columnType={columnType}
                                                            columnIndex={columnIndex}
                                                            customValue={customValue}
                                                            originalValue={originalValue}
                                                            validationErrors={validationErrors}
                                                        />
                                                    </td>
                                                );
                                            })}

                                            <td style={{textAlign: "right"}}>
                                                <button
                                                    className="pure-button danger"
                                                    onClick={preventDefault(_ => this.props.dropRow(rowIndex))}
                                                >
                                                    <Icon icon="trash" />
                                                </button>
                                            </td>
                                        </tr>
                                    );

                                })}

                            </tbody>

                        </table>

                    </div>

                    <div className="pure-g" style={{marginTop: "50px"}}>
                        <div className="pure-u-4-5">

                            {!areAllRowsOk(rowStatus) &&
                            <button className="pure-button pure-button-primary"
                                style={{fontSize: "200%"}}
                                disabled={missingColumns.length > 0 || !hasValuesInRequiredCells(columns, rows)}
                                onClick={this.startImport.bind(this)}>{t("start_import")}</button>}

                            {areAllRowsOk(rowStatus) && <ResetPWButton />}

                        </div>

                        {missingColumns.length > 0 &&
                        <div className="pure-u-1-5">
                            <div className="ImportTool-error-well">
                                <h4>{t("missing_columns")}</h4>
                                <ul>
                                    {missingColumns.map(c => <li key={c.id}>{t.type(c.id)}</li>)}
                                </ul>
                            </div>
                        </div>}
                    </div>
                </div>}


            </div>
        );
    }
}

class ResetPWButton extends PureComponent {
    constructor(props) {
        super(props);
        this.state = {resetAll: false};
    }

    render() {
        return (
            <div>
                <button
                    style={{fontSize: "200%"}}
                    className="pure-button pure-button-primary danger"
                    onClick={preventDefault(_ => {
                        this.props.createPasswordResetIntentForNewUsers({resetAll: this.state.resetAll});
                    })}>
                    {t("reset_passwords")}
                </button>
                <div>
                    <label>
                        <input
                            type="checkbox"
                            onChange={_ => this.setState({resetAll: !this.state.resetAll})}
                            checked={this.state.resetAll} />
                        {t("reset_existing_users")}
                    </label>
                </div>
            </div>
        );
    }
}
ResetPWButton.propTypes = {
    createPasswordResetIntentForNewUsers: React.PropTypes.func.isRequired,
};
ResetPWButton = connect(null, {createPasswordResetIntentForNewUsers})(ResetPWButton);


ImportTool.propTypes = {
    startImport: React.PropTypes.func.isRequired,
    dropRow: React.PropTypes.func.isRequired,
    rows: React.PropTypes.array.isRequired,
    columns: React.PropTypes.array.isRequired,
    rowStatus: React.PropTypes.object.isRequired,
    findMissingRequiredColumns: React.PropTypes.func.isRequired,
};

export default connect(({rowStatus, rows, columns, activeColumnTypes}) => {
    const findMissingRequiredColumns = R.differenceWith(
        R.eqProps("id"),
        pickRequiredColumns(activeColumnTypes)
    );
    return {
        rowStatus,
        rows,
        columns,
        findMissingRequiredColumns,
    };
},{
    parseImportString,
    startImport,
    dropRow,
})(ImportTool);
