/*eslint comma-dangle:0*/
var webpack = require("webpack");

var config = {
    entry: [
        "webpack-hot-middleware/client?path=http://puavo-standalone.opinsys.net:4000/__webpack_hmr",
        "./import-tool/index.js",
    ],
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js"
    },
    devtool: "cheap-module-eval-source-map",
    module: {
        loaders: [
            {
                test: /\.jsx?$/,
                exclude: /node_modules/,
                loader: "babel",
                query: {
                    "env": {
                        "development": {
                            "plugins": ["react-transform"],
                            "extra": {
                                "react-transform": [{
                                    "target": "react-transform-hmr",
                                    "imports": ["react"],
                                    "locals": ["module"]
                                }]
                            }
                        }
                    }
                }
            }
        ]
    },
    plugins: [
        new webpack.DefinePlugin({
            "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV)
        })
    ]
};

if (process.env.NODE_ENV === "production") {
    config.devtool = "source-map";
    config.entry = "./import-tool/index.js";
    config.plugins = config.plugins.concat([
        new webpack.ExtendedAPIPlugin(),
    ]);
} else {
    config.output.publicPath = "http://puavo-standalone.opinsys.net:4000/";
    config.plugins = config.plugins.concat([
        new webpack.HotModuleReplacementPlugin(),
        new webpack.NoErrorsPlugin(),
    ]);
}

module.exports = config;
