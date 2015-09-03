
import React from "react";
import R from "ramda";
import {connect} from "react-redux";
import PureComponent from "react-pure-render/component";
import Modal from "./Modal";

import ColumnTypes, {REQUIRED_COLUMNS} from "../ColumnTypes";
import {parseImportString, startImport, dropRow} from "../actions";
import Cell from "./Cell";
import ImportMenu from "./ImportMenu";
import ColumnEditor from "./ColumnEditor";
import Fa from "./Fa";
import {getCellValue, preventDefault} from "../utils";

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
        this.state = {
            importString: "",
            showModalFor: null,
        };
    }

    parseImportString(e) {
        this.props.parseImportString(this.state.importString || demoData);
    }

    startImport() {
        this.props.startImport();
    }

    startFileDialog(e) {
        React.findDOMNode(this.refs.file).click();
    }

    readFileEvent(e) {
        var file = e.target.files[0];
        if (!file) return;
        var reader = new FileReader();
        reader.onload = e => {
            this.setState({importString: e.target.result});
        };
        reader.readAsText(file);
    }

    render() {
        const {columns, rows, rowStatus} = this.props;
        const missingColumns = findMissingRequiredColumns(columns);

        return (
            <div className="ImportTool">
                {this.state.showModalFor !== null &&
                <Modal show onHide={e => this.setState({showModalFor: null})}>
                    <div>
                        <h2>row {this.state.showModalFor}</h2>
                        <pre>
                            {JSON.stringify(rowStatus[this.state.showModalFor], null, "  ")}
                        </pre>
                    </div>
                </Modal>}

                {rows.length == 0 &&
                <form className="ImportTool-data-selector pure-form" >
                    <textarea
                        className="ImportTool-textarea"
                        placeholder={demoData}
                        value={this.state.importString}
                        onChange={e => this.setState({importString: e.target.value})}
                    />

                    <div className="pure-g">
                        <div className="pure-u-4-5">
                            <button
                                className="pure-button pure-button-primary"
                                style={{width: "100%"}}
                                onClick={preventDefault(this.parseImportString.bind(this))}>Parse</button>
                        </div>
                        <div className="pure-u-1-5">
                            <button
                                className="pure-button"
                                style={{width: "100%"}}
                                onClick={preventDefault(this.startFileDialog.bind(this))}>Load file</button>
                        </div>
                    </div>

                    <input
                        type="file"
                        style={{display: "none"}}
                        ref="file"
                        accept=".csv,.txt,.tsv,.tab"
                        onChange={this.readFileEvent.bind(this)} />

                </form>}

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
    parseImportString: React.PropTypes.func.isRequired,
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
