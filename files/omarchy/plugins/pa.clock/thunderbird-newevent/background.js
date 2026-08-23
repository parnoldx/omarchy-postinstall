// The whole add-on is the experiment API; the background page exists only to
// hand it the file to watch, so the path lives in one place instead of being
// hardcoded on both sides of the WebExtension boundary. Relative to $HOME,
// which the parent resolves — a background page has no notion of the profile's
// home directory.
const REQUEST_FILE = ".local/state/omarchy/thunderbird-new-event.json";

browser.omarchyNewEvent.watch(REQUEST_FILE);
