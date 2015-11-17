
import React from "react";
import PureComponent from "./PureComponent";
import {connect} from "react-redux";

import t from "../i18n";

import ErrorModalButton from "./ErrorModalButton";

class GroupSelector extends PureComponent {

    onChange(e) {
        if (e.target.value === "nil") return;
        this.props.onChange(e);
    }

    render() {
        return (
            <select value={this.props.value} onChange={this.onChange.bind(this)}>
                <option key="nil" value="nil">Select...</option>
                {this.props.groups.map(group =>
                    <option key={group.id} value={group.abbreviation}>{group.name}</option>
                )}
            </select>
        );
    }
}
GroupSelector.propTypes = {
    groups: React.PropTypes.array.isRequired,
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};
GroupSelector = connect(({groups}) => ({groups}))(GroupSelector);


class Group extends PureComponent {
    render() {
        return (
            <span>
                {this.props.unknown &&
                <ErrorModalButton tooltip={t("unknown_group")}>
                    <p>
                        {t("unknown_group")} <span style={{fontStyle: "italic"}}>{this.props.abbreviation}</span>
                    </p>
                    <p>
                        {t("known_group")}
                    </p>
                    <ul>
                        {this.props.groups.map(r => <li key={r.id} style={{fontStyle: "italic"}}>{r.abbreviation}</li>)}
                    </ul>
                </ErrorModalButton>}

                {this.props.name}
                {" "}
                <small>({this.props.abbreviation})</small>

            </span>
        );
    }
}
Group.propTypes = {
    abbreviation: React.PropTypes.string.isRequired,
    name: React.PropTypes.string,
    unknown: React.PropTypes.bool.isRequired,
    groups: React.PropTypes.array.isRequired,
};
Group = connect(({groups}, {abbreviation}) => {
    abbreviation = String(abbreviation || "").trim();
    const group  = groups.find(r => r.abbreviation === abbreviation);
    return {
        groups,
        name: group && group.name,
        abbreviation,
        unknown: !!(abbreviation && !group),
    };
})(Group);


export {Group, GroupSelector};
