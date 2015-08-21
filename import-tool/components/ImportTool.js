
import R from "ramda";
import React from "react";
import {connect} from "react-redux";

import {setImportData, startImport} from "../actions";
import Cell from "./Cell";
import AddColumn from "./AddColumn";
import ColumnTypeSelector from "./ColumnTypeSelector";

const demoData = `
Bob, Brown, bob@examle.com
Alice, Smith, alice@example.com
Charlie, Chaplin, charlie@exampl.com
`;


export default class ImportTool extends React.Component {

    onParseCSV(e) {
        var el = React.findDOMNode(this.refs.textarea);
        this.props.setImportData(el.value);
    }

    startImport() {
        this.props.startImport(this.props.importData);
    }

    render() {
        var {columns, rows} = this.props.importData;

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
    importData: React.PropTypes.object.isRequired,
};

export default connect(R.identity, {setImportData, startImport})(ImportTool);
