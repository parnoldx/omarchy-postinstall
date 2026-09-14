const test = require("node:test")
const assert = require("node:assert/strict")
const MenuModel = require("../MenuModel.js")

function catalog() {
  const app = {
    id: "apps.microsoft-edge",
    parent: "apps",
    kind: "app",
    label: "Microsoft Edge",
    aliases: [],
    description: "Web Browser",
    order: 400
  }
  const setup = {
    id: "setup.default.browser.edge",
    parent: "setup.default.browser",
    kind: "action",
    label: "Edge",
    aliases: [],
    description: "",
    order: 150
  }
  const remove = {
    id: "remove.browser.edge",
    parent: "remove.browser",
    kind: "action",
    label: "Edge",
    aliases: [],
    description: "",
    order: 200
  }
  const channel = {
    id: "update.channel.edge",
    parent: "update.channel",
    kind: "action",
    label: "Edge",
    aliases: [],
    description: "",
    order: 250
  }
  const items = {
    root: { id: "root", parent: "", kind: "menu", label: "Go" },
    apps: { id: "apps", parent: "root", kind: "menu", label: "Apps" },
    setup: { id: "setup", parent: "root", kind: "menu", label: "Setup" },
    "setup.default": { id: "setup.default", parent: "setup", kind: "menu", label: "Default" },
    "setup.default.browser": { id: "setup.default.browser", parent: "setup.default", kind: "menu", label: "Browser" },
    remove: { id: "remove", parent: "root", kind: "menu", label: "Remove" },
    "remove.browser": { id: "remove.browser", parent: "remove", kind: "menu", label: "Browser" },
    update: { id: "update", parent: "root", kind: "menu", label: "Update" },
    "update.channel": { id: "update.channel", parent: "update", kind: "menu", label: "Channel" }
  }
  items[app.id] = app
  items[setup.id] = setup
  items[remove.id] = remove
  items[channel.id] = channel
  return { items, app, setup, remove, channel }
}

function ranked(items, entries, query) {
  return entries
    .map(function(entry) {
      return { id: entry.id, kind: entry.kind, score: MenuModel.searchScore(items, entry, query) }
    })
    .sort(function(a, b) { return a.score - b.score })
}

test("a matching app ranks above menu rows that only share a label prefix", () => {
  const { items, app, setup, remove, channel } = catalog()
  const entries = [app, setup, remove, channel]

  for (const query of ["edg", "edge"]) {
    const order = ranked(items, entries, query)
    assert.equal(order[0].id, app.id, query)
    assert.ok(order.slice(1).every(function(row) { return row.kind !== "app" }), query)
  }
})

test("an exact app name still beats an exact menu label", () => {
  const { items, app, setup } = catalog()
  assert.ok(MenuModel.searchScore(items, app, "edge") < MenuModel.searchScore(items, setup, "edge"))
})
