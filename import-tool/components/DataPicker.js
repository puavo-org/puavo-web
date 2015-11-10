
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";

import {parseImportString} from "../actions";
import {preventDefault} from "../utils";
import t from "../i18n";

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


// http://stackoverflow.com/questions/3308292/inserting-text-at-cursor-in-a-textarea-with-javascript/3308539#3308539
function insertTextAtCursor(el, text) {
    var val = el.value, endIndex, range;
    if (typeof el.selectionStart != "undefined" && typeof el.selectionEnd != "undefined") {
        endIndex = el.selectionEnd;
        el.value = val.slice(0, el.selectionStart) + text + val.slice(endIndex);
        el.selectionStart = el.selectionEnd = endIndex + text.length;
    } else if (typeof document.selection != "undefined" && typeof document.selection.createRange != "undefined") {
        el.focus();
        range = document.selection.createRange();
        range.collapse(false);
        range.text = text;
        range.select();
    }
}


class DataPicker extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {importString: ""};
    }

    parseImportString(e) {
        this.props.parseImportString(this.state.importString || demoData);
    }

    startFileDialog(e) {
        this.refs.file.click();
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

    onTab(e) {
        if (e.key === "Tab") {
            e.preventDefault();
            insertTextAtCursor(this.refs.textarea, "	");
        }
    }

    render() {
        return (
            <form className="ImportTool-DataPicker pure-form" >
                <textarea
                    ref="textarea"
                    className="ImportTool-textarea"
                    onKeyDown={this.onTab.bind(this)}
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
                            onClick={preventDefault(this.parseImportString.bind(this))}>{t("begin")}</button>
                    </div>
                    <div className="pure-u-1-5">
                        <button
                            className="pure-button button-large"
                            style={{width: "100%"}}
                            onClick={preventDefault(this.startFileDialog.bind(this))}>{t("select_file")}</button>
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
