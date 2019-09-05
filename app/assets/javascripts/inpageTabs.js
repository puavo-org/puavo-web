// Simple in-page tabs

// Experimental prototype

class Tabs {
    constructor(tabBarId, initialTabIndex=0)
    {
        this.container = document.getElementById(tabBarId);

        if (this.container === null) {
            console.error(`tab container "${tabBarId}" not found`);
            return;
        }

        var tabItems = this.container.children[0].children;

        // Gather up the A elements in the UL and their target DIVs
        this.tabs = [];

        for (var i = 0; i < tabItems.length; i++) {
            var a = tabItems[i].children[0];
            const targetId = a.href.split("#")[1];

            a.addEventListener("click", event => this.onTabClicked(event));
            a.dataset.index = i;
            this.tabs.push([a, document.getElementById(targetId)]);
        }

        if (this.tabs.length == 0) {
            console.error(`no tab elements found in "{tabBarId}"`);
            return;
        }

        // Activate the initial tab
        this.activeTab = initialTabIndex;

        if (this.activeTab < 0 || this.activeTab > this.tabs.length - 1)
            this.activeTab = 0;

        this.changeTab(this.activeTab);
    }

    onTabClicked(event)
    {
        this.changeTab(event.target.dataset.index);
        event.preventDefault();
    }

    changeTab(index)
    {
        for (var i = 0; i < this.tabs.length; i++) {
            if (i == index) {
                // Show this tab
                this.tabs[i][0].classList.add("tabActive");
                this.tabs[i][1].className = "tabContentsVisible";
            } else {
                // Hide this tab
                this.tabs[i][0].classList.remove("tabActive");
                this.tabs[i][1].className = "tabContentsInvisible";
            }
        }
    }
};
