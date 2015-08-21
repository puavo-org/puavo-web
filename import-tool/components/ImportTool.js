
import R from "ramda";
import React from "react";
import {connect} from "react-redux";

import {setImportData, startImport} from "../actions";
import Cell from "./Cell";
import AddColumn from "./AddColumn";
import ColumnTypeSelector from "./ColumnTypeSelector";

const demoData = `
Bruce, Wayne, batman@example.com
Clark, Kent, superman@example.com
Peter, Parker, spiderman@example.com
Tony, Stark, ironman@example.com
Bruce, Banner, hulk@example.com
Matt, Murdock, daredevil@example.com
Oliver, Queen, arrow@example.com
James, Howlett, wolverine@example.com
`.trim();



export default class ImportTool extends React.Component {

    onParseCSV(e) {
        var el = React.findDOMNode(this.refs.textarea);
        this.props.setImportData(el.value);
    }

    startImport() {
        this.props.startImport();
    }

    render() {
        var {columns, rows, rowStatus} = this.props;

        return (
            <div className="ImportTool">

                {rows.length == 0 &&
                <div className="ImportTool-data-selector">
                    <textarea className="ImportTool-textarea" ref="textarea" defaultValue={demoData} />
                    <button onClick={this.onParseCSV.bind(this)}>Parse</button>
                </div>}


                <AddColumn />


                {rows.length > 0 &&
                <table>
                    <thead>
                        <tr>
                            <th>
                                Status
                            </th>

                            {columns.map((columnType, columnIndex) => {
                                return (
                                    <th>
                                        {columnType.name}
                                        <ColumnTypeSelector columnIndex={columnIndex} />
                                    </th>
                                );
                            })}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((row, rowIndex) => {
                            return (
                                <tr>
                                    <td>
                                        {rowStatus[rowIndex] || "waiting"}
                                    </td>
                                    {columns.map((columnType, columnIndex) => {
                                        return (
                                            <td>
                                                <Cell value={row[columnIndex]} rowIndex={rowIndex} columnIndex={columnIndex} />
                                            </td>
                                        );
                                    })}
                                </tr>
                            );

                        })}

                    </tbody>

                </table>}

                <button onClick={this.startImport.bind(this)}>import</button>
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
