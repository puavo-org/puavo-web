
import React from "react";
import {Cond, Clause, Default} from "react-cond";

import t from "../i18n";
import {CREATE_USER, UPDATE_SCHOOL, UPDATE_ALL} from "../actions";

import PureComponent from "./PureComponent";
import {RadioSelect, RadioOption} from "./RadioSelect";




export class UpdateType extends PureComponent {
    render() {

        return (
            <Cond value={this.props.value}>
                <Clause test={CREATE_USER}>
                    <span>{t("create_user")}</span>
                </Clause>
                <Clause test={UPDATE_SCHOOL}>
                    <span>{t("update_school")}</span>
                </Clause>
                <Clause test={UPDATE_ALL}>
                    <span>{t("update_all")}</span>
                </Clause>
                <Default>
                    <span>{t("create_user")}</span>
                </Default>
            </Cond>
        );
    }
}
UpdateType.propTypes = {
    value: React.PropTypes.bool.isRequired,
};


export class UpdateTypeInput extends PureComponent {

    render() {
        return (
            <div>
                <RadioSelect {...this.props}>
                    <RadioOption value={CREATE_USER}>
                        {t("create_user")}
                    </RadioOption>
                    <RadioOption value={UPDATE_SCHOOL}>
                        {t("update_school")}
                    </RadioOption>
                    <RadioOption value={UPDATE_ALL}>
                        {t("update_all")}
                    </RadioOption>
                </RadioSelect>
            </div>
        );
    }
}
UpdateTypeInput.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};

