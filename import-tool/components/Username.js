
import React from "react";
import ReactDOM from "react-dom";
import R from "ramda";
import {connect} from "react-redux";
import {Cond, Clause, Default} from "react-cond";
import debounce from "lodash/function/debounce";

import t from "../i18n";
import {GENERATE_USERNAME} from "../constants";
import {AllColumnTypes} from "../ColumnTypes";
import {setVisibleUsernames} from "../actions";

import PureComponent from "./PureComponent";
import StatusIcon from "./StatusIcon";

const SimpleIcon = ({title, children}) => <span title={title} style={{marginLeft: 3, fontWeight: "bold"}}>{children}</span>;


// http://stackoverflow.com/a/7557433/153718
function isElementInViewport (el) {
    if (!el) return false;

    var rect = el.getBoundingClientRect();

    return (
        rect.top >= 0 &&
        rect.left >= 0 &&
        rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
        rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
}

const MOUNTED_NODES = [];

function startUsernameFetching() {
    if (MOUNTED_NODES.length === 0) return;
    const node = MOUNTED_NODES[0];

    node.props.setVisibleUsernames(
        MOUNTED_NODES
            .filter(n => isElementInViewport(ReactDOM.findDOMNode(n)))
            .filter(Boolean)
            .map(n => n.props.username)
    );

}


const debouncedStartFetch  = debounce(startUsernameFetching, 500);

window.addEventListener("scroll", debouncedStartFetch);
window.addEventListener("resize", debouncedStartFetch);


class Username extends PureComponent {

    componentDidMount() {
        MOUNTED_NODES.push(this);
    }

    componentWillUnmount() {
        const i = MOUNTED_NODES.indexOf(this);
        if (i !== -1) {
            MOUNTED_NODES.splice(i, 1);
        }
    }

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
}, {setVisibleUsernames})(Username);


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


const isFirstName = R.equals(AllColumnTypes.first_name);
const isLastName = R.equals(AllColumnTypes.last_name);
const canGenerateUsername = R.allPass(R.map(R.any, [isFirstName, isLastName]));

UsernameInput = connect(state => {
    return {canGenerateUsername: canGenerateUsername(state.columns)};
})(UsernameInput);


export {Username, UsernameInput};
