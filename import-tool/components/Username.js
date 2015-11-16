
import React from "react";
import R from "ramda";
import {connect} from "react-redux";
import {Cond, Clause, Default} from "react-cond";

import t from "../i18n";
import {GENERATE_USERNAME} from "../constants";
import ColumnTypes from "../ColumnTypes";

import PureComponent from "./PureComponent";
import StatusIcon from "./StatusIcon";

const SimpleIcon = ({children}) => <span style={{marginLeft: 3, fontWeight: "bold"}}>{children}</span>;

class Username extends PureComponent {
    render() {
        const {username, userData} = this.props;
        const school = R.path(["userData", "schools", 0], this.props);

        return (
            <span>
                {school &&
                <a title={`${userData.first_name} ${userData.last_name}`} href={`/users/${school.id}/users/${userData.id}`}>{username}</a>}
                {!school && username}

                <Cond value={this.props.userDataState}>
                    <Clause test={R.equals("fetching")}>
                        <StatusIcon status="working" />
                    </Clause>
                    <Clause test={R.equals("error")}>
                        <SimpleIcon title="Error while loading user data. Check the logs">ERR</SimpleIcon>
                    </Clause>
                    <Clause test={R.equals("notfound")}>
                        <StatusIcon status="ok" title={t("user_not_found")} />
                    </Clause>
                    <Clause test={R.equals("ok")}>
                        <StatusIcon status="error" title={t("user_exists")} />
                    </Clause>
                    <Clause test={_ => !!username}>
                        <SimpleIcon title={t("waiting_user_data")}>?</SimpleIcon>
                    </Clause>
                    <Default>
                        <span></span>
                    </Default>
                </Cond>

                {school &&
                <span style={{fontSize: "8pt"}}>
                    <br />
                    {school.name} ({school.groups.map(R.prop("name")).join(", ")})
                </span>}


            </span>
        );
    }
}
Username.propTypes = {
    username: React.PropTypes.string.isRequired,
    userData: React.PropTypes.object,
    userDataState: React.PropTypes.string,
};
Username = connect((state, props) => {
    const username = R.trim(props.username);
    return {
        userDataState: R.path(["userCache", username, "state"], state),
        userData: R.path(["userCache", username, "userData"], state),
    };
})(Username);


class UsernameInput extends PureComponent {

    componentDidMount() {
        if (this.refs.input) {
            this.refs.input.select();
        }
    }

    render() {
        const generate = this.props.value === GENERATE_USERNAME;

        return (
            <span>
                <input
                    ref="input"
                    type="text"
                    onChange={this.props.onChange}
                    value={this.props.value}
                    disabled={generate} />
                <label style={{fontSize: "small"}}>
                    <input
                        type="checkbox"
                        disabled={!this.props.canGenerateUsername}
                        onChange={_ => {
                            if (generate) {
                                this.props.onChange({target: {value: ""}});
                            } else {
                                this.props.onChange({target: {value: GENERATE_USERNAME}});
                            }
                        }}
                        checked={generate}
                    />
                    {t("generate_username")}
                </label>
                {!this.props.canGenerateUsername &&
                <p style={{fontSize: "small", fontStyle: "italic"}}>
                    {t("add_names_to_generate_username")}
                </p>}
            </span>
        );

    }
}
UsernameInput.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
    canGenerateUsername: React.PropTypes.bool.isRequired,
};


const isFirstName = R.equals(ColumnTypes.first_name);
const isLastName = R.equals(ColumnTypes.last_name);
const canGenerateUsername = R.allPass(R.map(R.any, [isFirstName, isLastName]));

UsernameInput = connect(state => {
    return {canGenerateUsername: canGenerateUsername(state.columns)};
})(UsernameInput);


export {Username, UsernameInput};
