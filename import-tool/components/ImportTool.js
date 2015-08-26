
import React from "react";
import R from "ramda";
import {connect} from "react-redux";
import PureComponent from "react-pure-render/component";

import {REQUIRED_COLUMNS} from "../column_types";
import {setImportData, startImport} from "../actions";
import Cell from "./Cell";
import AddColumn from "./AddColumn";
import ColumnTypeSelector from "./ColumnTypeSelector";
import {getCellValue} from "../utils";

const demoData = `
Bruce, Wayne, batman@example.com
Clark, Kent, superman@example.com
Peter, Parker, spiderman@example.com
Tony, Stark, ironman@example.com, boss
Bruce, Banner, hulk@example.com
Matt, Murdock, daredevil@example.com
Oliver, Queen, arrow@example.com
James, Howlett, wolverine@example.com
`.trim();


const findMissingRequiredColumns = R.difference(REQUIRED_COLUMNS);

const isRequired = R.propEq("required", true);

function hasValueInRequiredCells(columns, rows) {
    return rows.every(row => {
        return columns.every((column, i) => {
            if (!isRequired(column)) return true;
            return !!getCellValue(row[i]);
        });
    });
}

export default class ImportTool extends PureComponent {

    onParseCSV(e) {
        var el = React.findDOMNode(this.refs.textarea);
        this.props.setImportData(el.value);
    }

    startImport() {
        this.props.startImport();
    }

    render() {
        const {columns, rows, rowStatus} = this.props;
        const missingColumns = findMissingRequiredColumns(columns);

        return (
            <div className="ImportTool">

                {rows.length == 0 &&
                <div className="ImportTool-data-selector" >
                    <textarea className="ImportTool-textarea" ref="textarea" defaultValue={demoData} />
                    <button onClick={this.onParseCSV.bind(this)}>Parse</button>
                </div>}

                {rows.length > 0 &&
                <div className="ImportTool-editor">
                    data: {hasValueInRequiredCells(columns, rows) ? "ok" : "no"}
                    <table>
                        <thead>
                            <tr>
                                <th key="status">
                                    Status
                                </th>

                                {columns.map((columnType, columnIndex) => {
                                    return (
                                        <th key={columnIndex}>
                                            {columnType.name}
                                            <ColumnTypeSelector columnIndex={columnIndex} />
                                        </th>
                                    );
                                })}
                                <th>
                                    Add column
                                    <br />
                                    <AddColumn />
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {rows.map((row, rowIndex) => {
                                return (
                                    <tr key={rowIndex}>
                                        <td>
                                            {R.path([rowIndex, "status"], rowStatus) || "waiting"}
                                        </td>
                                        {columns.map((columnType, columnIndex) => {
                                            return (
                                                <td key={columnIndex}>
                                                    <Cell value={row[columnIndex]} rowIndex={rowIndex} columnIndex={columnIndex} />
                                                </td>
                                            );
                                        })}
                                    </tr>
                                );

                            })}

                        </tbody>

                    </table>

                    <h4>Missing required columns</h4>
                    <ul>
                        {missingColumns.map(c => <li key={c.id}>{c.name}</li>)}
                    </ul>

                </div>}


                <button
                    disabled={missingColumns.length > 0 || !hasValueInRequiredCells(columns, rows)}
                    onClick={this.startImport.bind(this)}>import</button>
            </div>
        );
    }
}

ImportTool.propTypes = {
    setImportData: React.PropTypes.func.isRequired,
    startImport: React.PropTypes.func.isRequired,
    rows: React.PropTypes.array.isRequired,
    columns: React.PropTypes.array.isRequired,
    rowStatus: React.PropTypes.object.isRequired,
};

function select(state) {
    var {rowStatus, importData: {rows, columns}} = state;
    return {rowStatus, rows, columns};
}

export default connect(select, {setImportData, startImport})(ImportTool);
