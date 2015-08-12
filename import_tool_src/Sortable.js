"use strict";

var React = require("react");
var classSet = require("class-set");
var R = require("ramda");

var Sortable = React.createClass({

    propTypes: {
        children: React.PropTypes.node,
        rowClassNameGetter: React.PropTypes.func,
        rows: React.PropTypes.array.isRequired,
        paginate: React.PropTypes.number,
        rowKeyGetter: React.PropTypes.func
    },

    getInitialState() {

        var sortBy = this.getColumns().reduce((memo, column, columnId) => {
            if (column.props.defaultSort) {
                return {
                    columnId,
                    order: column.props.initialSortOrder
                };
            }
            return memo;
        }, null);

        if (!sortBy) throw new Error("Must add 'defaultSort' prop for one the Column components");

        return {
            sortBy,
            currentPage: 0
        };
    },

    isPaginationActive() {
        return this.props.paginate && this.props.paginate < this.props.rows.length;
    },

    nextPage() {
        this.setState({ currentPage: this.state.currentPage + 1 });
    },

    prevPage() {
        this.setState({ currentPage: this.state.currentPage - 1 });
    },

    renderPager() {
        if (!this.isPaginationActive()) return null;

        var rowCount = this.props.rows.length;
        var rowsPerPage = this.props.paginate;
        var currentPage = this.state.currentPage + 1;
        var pageCount = Math.ceil(rowCount / rowsPerPage);

        return (
            <nav>
                <ul className="pager">
                    <li>
                        <a href="#"
                            disabled={currentPage === 1}
                            onClick={e => {
                                e.preventDefault();
                                if (currentPage === 1) return;
                                this.prevPage();
                            }}>◀</a>
                    </li>

                    <li>
                        <span>
                            {currentPage} / {pageCount}
                        </span>
                    </li>

                    <li>
                        <a href="#"
                            disabled={currentPage === pageCount}
                            onClick={e => {
                                e.preventDefault();
                                if (currentPage === pageCount) return;
                                this.nextPage();
                            }}>▶</a>
                    </li>
                </ul>
            </nav>
        );
    },

    getColumns() {
        return R.flatten(this.props.children).filter(Boolean);
    },

    toggleSort(columnId) {
        this.setState({currentPage: 0});

        if (columnId !== this.state.sortBy.columnId) {
            this.setState({sortBy: {
                columnId,
                order: this.getColumnProps(columnId).initialSortOrder
            }});
            return;
        }

        if (this.state.sortBy.order === "asc") {
            this.setState({ sortBy: { columnId, order: "desc" }});
        } else {
            this.setState({ sortBy: { columnId, order: "asc" }});
        }
    },

    getColumnProps(id) {
        return this.getColumns()[id].props;
    },

    render() {

        var rows = this.props.rows;
        var columns = this.getColumns();

        var sortOrder = this.state.sortBy.order;
        var sortColumn = columns[this.state.sortBy.columnId];

        rows = rows.slice().sort((a, b) => {
            a = sortColumn.props.sortDataGetter(a);
            b = sortColumn.props.sortDataGetter(b);

            if (sortOrder === "desc") {
                if(a < b) return 1;
                if(a > b) return -1;
            } else {
                if(a > b) return 1;
                if(a < b) return -1;
            }

            return 0;
        });


        if (this.isPaginationActive()) {
            let currentPage = this.state.currentPage;
            let rowsPerPage = this.props.paginate;
            let start = rowsPerPage * currentPage;
            rows = rows.slice(start, start + rowsPerPage);
        }

        return (
            <div className="Sortable table-responsive">

                {this.renderPager()}

                <table className="table table-hover">
                    <thead>
                        <tr>
                            {columns.map((c, columnId) => {
                                return (
                                    <th key={columnId}>
                                        {c.props.children}

                                        <a href="#"
                                            className={classSet({
                                                "Sortable-sort-btn": true,
                                                "active": this.state.sortBy.columnId === columnId
                                            })}
                                            onClick={e => {
                                            e.preventDefault();
                                            this.toggleSort(columnId);
                                        }}>
                                        {sortOrder === "asc" ? "▲" : "▼"}
                                        </a>
                                    </th>
                                );
                            })}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((row, rowNum) => {
                            var className = "";

                            var rowKey = rowNum;

                            if (typeof this.props.rowKeyGetter === "function") {
                                rowKey = this.props.rowKeyGetter(row);
                            }

                            if (typeof this.props.rowClassNameGetter === "function") {
                                className = this.props.rowClassNameGetter(row);
                            }

                            return (
                                <tr key={rowKey} className={className}>
                                    {columns.map((c, tdId) => {
                                        return (
                                            <td key={tdId} className={c.props.className}>
                                                {c.props.render(row, rowNum)}
                                            </td>
                                        );
                                    })}
                                </tr>
                            );
                        })}
                    </tbody>
                </table>

                {this.renderPager()}

            </div>
        );
    }
});

var Column = React.createClass({

    propTypes: {
        className: React.PropTypes.string,
        initialSortOrder: React.PropTypes.oneOf(["desc", "asc"]),
        noSearch: React.PropTypes.bool,
        noSort: React.PropTypes.bool,
        defaultSort: React.PropTypes.bool,
        render: React.PropTypes.func.isRequired,
        sortDataGetter: React.PropTypes.func
    },

    getDefaultProps() {
        return {
            initialSortOrder: "desc",
            sortDataGetter: function(row) { return this.render(row); }
        };
    },

    render() {
        return this.props.children;
    }
});

Sortable.Column = Column;
Sortable.Sortable = Sortable;
module.exports = Sortable;
