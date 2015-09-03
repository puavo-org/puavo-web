
import React from "react";
import R from "ramda";
import {connect} from "react-redux";
import PureComponent from "react-pure-render/component";
import Modal from "./Modal";

import DataPicker from "./DataPicker";
import Cell from "./Cell";
import ImportMenu from "./ImportMenu";
import ColumnEditor from "./ColumnEditor";
import Fa from "./Fa";
import ColumnTypes, {REQUIRED_COLUMNS} from "../ColumnTypes";
import {parseImportString, startImport, dropRow} from "../actions";
import {getCellValue, preventDefault} from "../utils";

const findMissingRequiredColumns = R.difference(REQUIRED_COLUMNS);

const isRequired = R.propEq("required", true);

function hasValuesInRequiredCells(columns, rows) {
    return rows.every(row => {
        return columns.every((column, i) => {
            if (!isRequired(column)) return true;
            return !!getCellValue(row[i]);
        });
    });
}

export default class ImportTool extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {showModalFor: null};
    }

    startImport() {
        this.props.startImport();
    }

    render() {
        const {columns, rows, rowStatus} = this.props;
        const missingColumns = findMissingRequiredColumns(columns);

        return (
            <div className="ImportTool">
                {rows.length == 0 && <DataPicker />}

                {this.state.showModalFor !== null &&
                <Modal show onHide={e => this.setState({showModalFor: null})}>
                    <div>
                        <h2>row {this.state.showModalFor}</h2>
                        <pre>
                            {JSON.stringify(rowStatus[this.state.showModalFor], null, "  ")}
                        </pre>
                    </div>
                </Modal>}

                {rows.length > 0 &&
                <div className="ImportTool-editor">
                    <table className="pure-table pure-table-striped">
                        <thead>
                            <tr>
                                <th key="status">
                                    Status
                                </th>

                                {columns.map((columnType, columnIndex) => {
                                    return (
                                        <th key={columnIndex}>
                                            {columnType.name}{" "}
                                            <ColumnEditor
                                                columnIndex={columnIndex}
                                                currentTypeId={R.compose(
                                                    R.defaultTo(ColumnTypes.unknown.id),
                                                    R.path([columnIndex, "id"])
                                                )(columns)}
                                            />
                                        </th>
                                    );
                                })}
                                <th>
                                    <ImportMenu />
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {rows.map((row, rowIndex) => {
                                const rowStatusString = R.path([rowIndex, "status"], rowStatus) || "waiting";
                                return (
                                    <tr key={rowIndex}>
                                        <td>
                                            {rowStatusString}{" "}
                                            {!["ok", "waiting"].includes(rowStatusString) &&
                                            <a href="#" onClick={preventDefault(_ => this.setState({showModalFor: rowIndex}))}>
                                                <Fa icon="exclamation-triangle" className="error" />
                                            </a>}

                                        </td>

                                        {columns.map((columnType, columnIndex) => {
                                            return (
                                                <td key={columnIndex}>
                                                    <Cell
                                                        rowIndex={rowIndex}
                                                        columnIndex={columnIndex}
                                                        value={getCellValue(R.path([rowIndex, columnIndex], rows))}
                                                        validationErrors={R.path([
                                                            rowIndex,
                                                            "attributeErrors",
                                                            columnType.attribute,
                                                        ], rowStatus)}
                                                    />
                                                </td>
                                            );
                                        })}

                                        <td>
                                            <button
                                                className="pure-button danger"
                                                onClick={preventDefault(_ => this.props.dropRow(rowIndex))}
                                            >
                                                <Fa icon="trash-o" />
                                            </button>
                                        </td>
                                    </tr>
                                );

                            })}

                        </tbody>

                    </table>

                    <h4>Missing required columns</h4>
                    <ul>
                        {missingColumns.map(c => <li key={c.id}>{c.name}</li>)}
                    </ul>

                    <button className="pure-button"
                        disabled={missingColumns.length > 0 || !hasValuesInRequiredCells(columns, rows)}
                        onClick={this.startImport.bind(this)}>import</button>

                </div>}


            </div>
        );
    }
}

ImportTool.propTypes = {
    startImport: React.PropTypes.func.isRequired,
    dropRow: React.PropTypes.func.isRequired,
    rows: React.PropTypes.array.isRequired,
    columns: React.PropTypes.array.isRequired,
    rowStatus: React.PropTypes.object.isRequired,
};

function select(state) {
    var {rowStatus, importData: {rows, columns}} = state;
    return {rowStatus, rows, columns};
}

export default connect(select, {parseImportString, startImport, dropRow})(ImportTool);
