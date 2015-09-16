
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";

import {parseImportString} from "../actions";
import {preventDefault} from "../utils";

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


class DataPicker extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {importString: ""};
    }

    parseImportString(e) {
        this.props.parseImportString(this.state.importString || demoData);
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
        return (
            <form className="ImportTool-DataPicker pure-form" >
                <textarea
                    className="ImportTool-textarea"
                    style={{width: "100%", height: 300}}
                    placeholder={demoData}
                    value={this.state.importString}
                    onChange={e => this.setState({importString: e.target.value})}
                />

                <div className="pure-g">
                    <div className="pure-u-4-5">
                        <button
                            className="pure-button pure-button-primary button-large"
                            style={{width: "100%"}}
                            onClick={preventDefault(this.parseImportString.bind(this))}>Parse</button>
                    </div>
                    <div className="pure-u-1-5">
                        <button
                            className="pure-button button-large"
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

            </form>
        );
    }

}

DataPicker.propTypes = {
    parseImportString: React.PropTypes.func.isRequired,
};

export default connect(null, {parseImportString})(DataPicker);
