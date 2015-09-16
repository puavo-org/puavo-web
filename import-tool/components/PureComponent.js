
import React from "react";
import R from "ramda";
import shouldPureComponentUpdate from "react-pure-render/function";

var tickExecuting = false;
var updates = 0;
var componentCount = 0;
var componentNames = {};

const format = R.compose(
    R.join(" "),
    R.map(([name, count]) => `${name}(${count})`),
    R.sort(([__, a], [_, b]) => b - a),
    R.toPairs
);

function stopLogging() {
    console.log(`Updated ${updates}/${componentCount} components ${format(componentNames)}`);
    componentNames = {};
    tickExecuting = false;
    updates = 0;
    componentCount = 0;
}


/**
 * Pure render component which logs staticstics for component updates for each
 * tick
 */
export default class PureComponent extends React.Component {
    shouldComponentUpdate(nextProps, nextState) {
        var shouldUpdate = shouldPureComponentUpdate.call(this, nextProps, nextState);

        if (process.env.NODE_ENV !== "production") {
            if (!tickExecuting) {
                setImmediate(stopLogging);
                tickExecuting = true;
            }

            componentCount++;

            if (shouldUpdate) {
                updates++;
                let name = this.constructor.name;
                componentNames[name] = (componentNames[name] || 0) + 1;
            }
        }

        return shouldUpdate;
    }
}
