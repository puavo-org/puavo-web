
import React from "react";
import PureComponent from "./PureComponent";

var i = 0;

export class RadioSelect extends PureComponent {

    constructor(props) {
        super(props);
        this.groupName = `generatedRadioButtonGroupName-${i++}`;
    }

    render() {
        return (
            <ul style={{padding: 0, margin: 0, textAlign: "left"}}>
                {this.props.children.map(option => {
                    const rEl = React.cloneElement(option, {
                        name: this.groupName,
                        onChange: this.props.onChange,
                        currentValue: this.props.value,
                    });

                    return <li>{rEl}</li>;
                })}
            </ul>
        );
    }
}
RadioSelect.propTypes = {
    onChange: React.PropTypes.func.isRequired,
    value: React.PropTypes.string.isRequired,
    children: React.PropTypes.node.isRequired,
};



export class RadioOption extends PureComponent {
    render() {
        const {children, ...restProps} = this.props;

        return (
            <label key={this.props.value}>
                <input
                    type="radio"
                    checked={restProps.value === restProps.currentValue}
                    {...restProps}
                />
                {children}
            </label>
        );
    }
}
RadioOption.propTypes = {
    children: React.PropTypes.node.isRequired,
    onChange: React.PropTypes.func.isRequired,
    key: React.PropTypes.string.isRequired,
    value: React.PropTypes.string.isRequired,
    name: React.PropTypes.string,
    currentValue: React.PropTypes.string,
};
