
import React from "react";
import PureComponent from "react-pure-render/component";

const ROLES = [
    {name: "Opettaja", value: "teacher"},
    {name: "Henkilökunta", value: "staff"},
    {name: "Oppilas", value: "student"},
    {name: "Vierailija", value: "visitor"},
    {name: "Vanhempi", value: "parent"},
    {name: "Ylläpitäjä", value: "admin"},
    {name: "Testikäyttäjä", value: "testuser"},
];

export class RoleSelector extends PureComponent {
    onChange(e) {
        if (e.target.value === "nil") return;
        this.props.onChange(e);
    }

    render() {
        return (
            <select value={this.props.value} onChange={this.onChange.bind(this)}>
                <option key="nil" value="nil">Select...</option>
                {ROLES.map(({name, value}) =>
                    <option key={value} value={value}>{name}</option>
                )}
            </select>
        );
    }

}

RoleSelector.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
};

export class Role extends PureComponent {
    render() {
        if (!this.props.value) return <span></span>;
        const role = ROLES.find(({name, value}) => value === this.props.value);
        const name = role ? role.name : <i>Tuntematon  {this.props.value}</i>;
        return <span>{name}</span>;
    }
}

Role.propTypes = {
    value: React.PropTypes.string.isRequired,
};
