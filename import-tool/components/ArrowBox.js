
import React from "react";
import PureComponent from "react-pure-render/component";

// Styles Mostly from Bootstrap
const BoxStyle = {
    position: "absolute",
    padding: "0 5px",
};

const borderColor = "#A36A2A";

const BoxInnerStyle = {
    boxShadow: "5px 5px 5px #888888",
    padding: "20px",
    textAlign: "center",
    borderRadius: 3,
    border: "5px solid " + borderColor,
    backgroundColor: "white",
};

const ArrowStyle = {
    position: "absolute",
    width: 0, height: 0,
    borderRightColor: "transparent",
    borderLeftColor: "transparent",
    borderTopColor: "transparent",
    borderBottomColor: "transparent",
    borderStyle: "solid",
};


const PlacementStyles = {
    left: {
        box: {marginLeft: -3, padding: "0 5px"},
        arrow: {
            right: 0, marginTop: -5, borderWidth: "5px 0 5px 5px", borderLeftColor: borderColor,
        },
    },
    right: {
        box: {marginRight: 3, padding: "0 5px"},
        arrow: {left: 0, marginTop: -5, borderWidth: "5px 5px 5px 0", borderRightColor: borderColor},
    },
    top: {
        box: {marginTop: -3, padding: "5px 0"},
        arrow: {bottom: 0, marginLeft: -5, borderWidth: "5px 5px 0", borderTopColor: borderColor},
    },
    bottom: {
        box: {marginBottom: 3, padding: "5px 0"},
        arrow: {top: 0, marginLeft: -5, borderWidth: "0 5px 5px", borderBottomColor: borderColor},
    },
};

export default class ArrowBox extends PureComponent {
    render() {
        let placementStyle = PlacementStyles[this.props.placement];

        let {style,
            arrowOffsetLeft: left = placementStyle.arrow.left,
            arrowOffsetTop: top = placementStyle.arrow.top,
            ...props} = this.props;

        return (
            <div style={{...BoxStyle, ...placementStyle.box, ...style}}>
                <div style={{...ArrowStyle, ...placementStyle.arrow, left, top}}/>
                <div style={BoxInnerStyle}>
                    {props.children}
                </div>
            </div>
        );
    }
}


ArrowBox.propTypes = {
    placement: React.PropTypes.string,
    style: React.PropTypes.object,
    arrowOffsetLeft: React.PropTypes.string,
    arrowOffsetTop: React.PropTypes.string,
};
