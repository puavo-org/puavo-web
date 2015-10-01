/*eslint comma-dangle:0*/

// Polyfill Promise global for style loaders
global.Promise = require("bluebird");
var execSync = require("exec-sync");
var webpack = require("webpack");

// This must be the public address where the hot reload bundle is loaded in the
// browser. Yeah it sucks to hard code it here. Let's hope for the better
// future
var PUBLIC_DEV_SERVER = process.env.PUBLIC_DEV_SERVER || "http://" + execSync("hostname -f") + ":4000/";

var ENTRY = "./import-tool/index.js";

var NODE_ENV_PLUGIN = new webpack.DefinePlugin({
    "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV)
});

var config = {
    entry: [
        "webpack-hot-middleware/client?path=" + PUBLIC_DEV_SERVER + "__webpack_hmr",
        ENTRY
    ],
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js",
        publicPath: PUBLIC_DEV_SERVER
    },
    devtool: "cheap-module-eval-source-map",
    module: {
        loaders: [
            {test: /\.css$/, loader: "style!css"},
            {
                test: /\.jsx?$/,
                exclude: /node_modules/,
                loader: "babel",
                query: {
                    "env": {
                        "development": {
                            "plugins": ["react-transform"],
                            "extra": {
                                "react-transform": {
                                    "transforms": [
                                        {
                                            "transform": "react-transform-hmr",
                                            "imports": ["react"],
                                            "locals": ["module"]
                                        }
                                    ]
                                }
                            }
                        }
                    }
                }
            }
        ]
    },
    plugins: [
        NODE_ENV_PLUGIN,
        new webpack.HotModuleReplacementPlugin(),
        new webpack.NoErrorsPlugin(),
    ]
};

// Drop all hot stuff for production!
if (process.env.NODE_ENV === "production") {
    config.devtool = "source-map";
    config.entry = ENTRY;
    delete config.output.publicPath;
    config.plugins = [
        NODE_ENV_PLUGIN,
        // We use __webpack_hash__ in production but the ExtendedAPIPlugin does
        // not work with hot mode.
        new webpack.ExtendedAPIPlugin(),
    ];
}

module.exports = config;
