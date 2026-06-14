import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io

Item {
    id: root
    width: Screen.width
    height: Screen.height

    property string home: Quickshell.env("HOME") || "/home/marinus"
    property string helper: home + "/.config/quickshell/widgets/llm-manager/llm-manager.py"
    property var state: ({ llama: { models: [] }, opencode: { agentFiles: [] }, pi: { agents: [] }, runtime: {}, validation: { errors: [], warnings: [] } })
    property int tab: 0
    property int selectedModel: 0
    property string agentSystem: "opencode"
    property int selectedAgent: 0
    property bool loading: false
    property bool dirty: false
    property string statusText: ""
    property string saveText: ""
    property string hfQuery: "Qwen GGUF"
    property var hfResults: []
    property int selectedHf: 0
    property var hfFiles: []
    property int selectedHfFile: 0
    property var localModels: []
    property int selectedLocal: 0
    property var cookbook: ({ system: {}, recipes: [] })
    property int selectedRecipe: 0
    property string browseStatus: ""
    property bool browseBusy: false
    // Cookbook search, filter, sort
    property string cookbookQuery: ""
    property string cookbookFilter: "all"
    property string cookbookSort: "fit"
    property var cookbookResults: []
    property int selectedCookbookResult: 0
    // User cookbook state
    property var userCookbook: ({ version: 1, recipes: {}, customRecipes: [] })
    property bool userCookbookDirty: false

    readonly property color cBg: "#111318"
    readonly property color cPanel: "#1b1f2a"
    readonly property color cPanel2: "#242a36"
    readonly property color cBorder: "#6ea6ff"
    readonly property color cFg: "#d8dee9"
    readonly property color cDim: "#9aa4b2"
    readonly property color cAccent: "#8fbcbb"
    readonly property color cWarn: "#ebcb8b"
    readonly property color cBad: "#bf616a"
    readonly property color cGood: "#a3be8c"

    function formatDate(d) {
        if (!d || d.length < 10) return d || "";
        var parts = d.split("T");
        return parts[0];
    }

    function runLoad() {
        loading = true;
        statusText = "Loading configs";
        loadProc.running = false;
        loadProc.running = true;
    }

    function modelList() {
        return state && state.llama && state.llama.models ? state.llama.models : [];
    }

    function agentList() {
        if (agentSystem === "pi") return state.pi && state.pi.agents ? state.pi.agents : [];
        return state.opencode && state.opencode.agentFiles ? state.opencode.agentFiles : [];
    }

    function currentModel() {
        let models = modelList();
        if (models.length === 0) return {};
        selectedModel = Math.max(0, Math.min(selectedModel, models.length - 1));
        return models[selectedModel];
    }

    function currentAgent() {
        let agents = agentList();
        if (agents.length === 0) return {};
        selectedAgent = Math.max(0, Math.min(selectedAgent, agents.length - 1));
        return agents[selectedAgent];
    }

    function setModelField(key, value) {
        let models = modelList();
        if (models.length === 0) return;
        models[selectedModel][key] = value;
        dirty = true;
    }

    function setAgentField(key, value) {
        let agents = agentList();
        if (agents.length === 0) return;
        agents[selectedAgent][key] = value;
        if (key === "id") {
            if (!agents[selectedAgent].frontmatter) agents[selectedAgent].frontmatter = {};
            agents[selectedAgent].frontmatter.name = value;
        }
        if (key === "model" || key === "mode" || key === "description") {
            if (!agents[selectedAgent].frontmatter) agents[selectedAgent].frontmatter = {};
            agents[selectedAgent].frontmatter[key] = value;
        }
        dirty = true;
    }

    function defaultAgentModel() {
        if (agentSystem === "pi" && state.pi && state.pi.defaultModel) return "llamaswap/" + state.pi.defaultModel;
        if (state.opencode && state.opencode.small_model) return state.opencode.small_model;
        let models = modelList().filter(function(m) { return !m.cpu; });
        return models.length > 0 ? "llamaswap/" + models[0].id : "";
    }

    function nextAgentId() {
        let base = "new-agent";
        let used = {};
        let agents = agentList();
        for (let i = 0; i < agents.length; i++) used[agents[i].id] = true;
        if (!used[base]) return base;
        for (let n = 2; n < 1000; n++) {
            let id = base + "-" + n;
            if (!used[id]) return id;
        }
        return base + "-" + Date.now();
    }

    function addAgent() {
        let id = nextAgentId();
        let model = defaultAgentModel();
        let prompt = "You are a specialized subagent. Describe this agent's responsibilities, tools, constraints, and expected output format.";
        let agent = {
            file: "",
            id: id,
            description: "New subagent",
            model: model,
            mode: agentSystem === "opencode" ? "subagent" : "",
            frontmatter: agentSystem === "opencode"
                ? {
                    name: id,
                    description: "New subagent",
                    mode: "subagent",
                    model: model,
                    permission: {
                        edit: "ask",
                        bash: { "*": "ask" },
                        read: "allow",
                        glob: "allow",
                        grep: "allow",
                        external_directory: "allow"
                    }
                }
                : {
                    name: id,
                    description: "New subagent",
                    tools: "read, grep, find, ls, bash, edit, write",
                    model: model
                },
            body: prompt
        };

        if (agentSystem === "pi") {
            if (!state.pi.agents) state.pi.agents = [];
            state.pi.agents.push(agent);
            selectedAgent = state.pi.agents.length - 1;
        } else {
            if (!state.opencode.agentFiles) state.opencode.agentFiles = [];
            state.opencode.agentFiles.push(agent);
            selectedAgent = state.opencode.agentFiles.length - 1;
        }
        dirty = true;
    }

    function refListText(list) {
        return (list || []).join("\n");
    }

    function refsFromText(text) {
        return String(text).split(/\n|,/).map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
    }

    function pushUnique(out, value) {
        value = String(value || "");
        if (value.length === 0) return;
        if (out.indexOf(value) < 0) out.push(value);
    }

    function modelRefOptions(current) {
        let out = [];
        let models = modelList();
        for (let i = 0; i < models.length; i++) {
            if (models[i].cpu) continue;
            pushUnique(out, "llamaswap/" + models[i].id);
            let aliases = models[i].aliases || [];
            for (let j = 0; j < aliases.length; j++) pushUnique(out, "llamaswap/" + aliases[j]);
        }
        pushUnique(out, current);
        return out;
    }

    function rawModelOptions(current) {
        let out = [];
        let models = modelList();
        for (let i = 0; i < models.length; i++) {
            if (models[i].cpu) continue;
            pushUnique(out, models[i].id);
        }
        pushUnique(out, current);
        return out;
    }

    function agentModeOptions(current) {
        let out = agentSystem === "opencode" ? ["subagent", "primary"] : ["", "subagent"];
        pushUnique(out, current);
        return out;
    }

    function defaultAgentOptions(current) {
        let out = [];
        let agents = state.opencode && state.opencode.agentFiles ? state.opencode.agentFiles : [];
        for (let i = 0; i < agents.length; i++) pushUnique(out, agents[i].id);
        pushUnique(out, current);
        return out;
    }

    function providerOptions(current) {
        let out = ["llamaswap"];
        pushUnique(out, current);
        return out;
    }

    function thinkingOptions(current) {
        let out = ["off", "minimal", "low", "medium", "high", "xhigh"];
        pushUnique(out, current);
        return out;
    }

    function closePanel() {
        Quickshell.execDetached([home + "/.config/quickshell/widgets/llm-manager/llm-manager-toggle.sh"]);
    }

    function currentHfModel() {
        if (!hfResults || hfResults.length === 0) return {};
        selectedHf = Math.max(0, Math.min(selectedHf, hfResults.length - 1));
        return hfResults[selectedHf];
    }

    function currentHfFile() {
        if (!hfFiles || hfFiles.length === 0) return {};
        selectedHfFile = Math.max(0, Math.min(selectedHfFile, hfFiles.length - 1));
        return hfFiles[selectedHfFile];
    }

    function currentLocalModel() {
        if (!localModels || localModels.length === 0) return {};
        selectedLocal = Math.max(0, Math.min(selectedLocal, localModels.length - 1));
        return localModels[selectedLocal];
    }

    function recipeList() {
        return cookbook && cookbook.recipes ? cookbook.recipes : [];
    }

    function currentRecipe() {
        let recipes = recipeList();
        if (recipes.length === 0) return {};
        selectedRecipe = Math.max(0, Math.min(selectedRecipe, recipes.length - 1));
        return recipes[selectedRecipe];
    }

    function systemSummary() {
        let system = cookbook && cookbook.system ? cookbook.system : {};
        let gpu = system.gpu || {};
        let configured = system.configured || {};
        let gpuText = gpu.ok ? ((gpu.name || "GPU") + " / " + String(gpu.vramGb || 0) + " GB VRAM") : ("Detected from router profile / " + String(system.effectiveVramGb || 0) + " GB VRAM target");
        let ctx = configured.maxContext ? (" / max router context " + String(configured.maxContext)) : "";
        return gpuText + ctx;
    }

    function loadLocalModels() {
        browseBusy = true;
        browseStatus = "Scanning local GGUF models";
        localProc.running = false;
        localProc.running = true;
    }

    function loadCookbook() {
        cookbookProc.running = false;
        cookbookProc.running = true;
    }

    function loadUserCookbook() {
        try {
            var content = Qt.readFromFile(home + "/.config/llm-manager/user-cookbook.json");
            if (content && content.trim().length > 0) {
                userCookbook = JSON.parse(content);
                if (!userCookbook.recipes) userCookbook.recipes = {};
                if (!userCookbook.customRecipes) userCookbook.customRecipes = [];
            }
        } catch (e) {
            userCookbook = { version: 1, recipes: {}, customRecipes: [] };
        }
        applyCookbookFilter();
    }

    function saveUserCookbook() {
        userCookbook.lastUpdated = new Date().toISOString();
        var content = JSON.stringify(userCookbook, null, 2);
        try {
            var file = Qt.openUrlWriteLocal(home + "/.config/llm-manager/user-cookbook.json");
            if (file) {
                file.write(content);
                file.close();
            }
        } catch (e) {
            Qt.writeToFile(home + "/.config/llm-manager/user-cookbook.json", content);
        }
        userCookbookDirty = false;
    }

    function getUserState(repo) {
        if (!userCookbook || !userCookbook.recipes) return {};
        return userCookbook.recipes[repo] || {};
    }

    function toggleFavorite(repo) {
        if (!userCookbook.recipes[repo]) userCookbook.recipes[repo] = {};
        userCookbook.recipes[repo].favorite = !userCookbook.recipes[repo].favorite;
        userCookbookDirty = true;
        applyCookbookFilter();
        // Persist to disk
        saveUserCookbook();
        // Also persist via CLI for reliability
        userStateProc.command = ["python3", root.helper, "set-favorite", JSON.stringify({ repo: repo, favorite: userCookbook.recipes[repo].favorite })];
        userStateProc.running = false;
        userStateProc.running = true;
    }

    function toggleTried(repo) {
        if (!userCookbook.recipes[repo]) userCookbook.recipes[repo] = {};
        userCookbook.recipes[repo].tried = !userCookbook.recipes[repo].tried;
        userCookbookDirty = true;
        applyCookbookFilter();
        saveUserCookbook();
        userStateProc.command = ["python3", root.helper, "set-tried", JSON.stringify({ repo: repo, tried: userCookbook.recipes[repo].tried })];
        userStateProc.running = false;
        userStateProc.running = true;
    }

    function setRating(repo, rating) {
        if (!userCookbook.recipes[repo]) userCookbook.recipes[repo] = {};
        userCookbook.recipes[repo].rating = rating;
        userCookbookDirty = true;
        applyCookbookFilter();
        saveUserCookbook();
        userStateProc.command = ["python3", root.helper, "set-rating", JSON.stringify({ repo: repo, rating: rating })];
        userStateProc.running = false;
        userStateProc.running = true;
    }

    function setNote(repo, note) {
        if (!userCookbook.recipes[repo]) userCookbook.recipes[repo] = {};
        userCookbook.recipes[repo].note = note;
        userCookbookDirty = true;
        applyCookbookFilter();
        saveUserCookbook();
        userStateProc.command = ["python3", root.helper, "set-note", JSON.stringify({ repo: repo, note: note })];
        userStateProc.running = false;
        userStateProc.running = true;
    }

    function applyCookbookFilter() {
        var recipes = cookbook && cookbook.recipes ? cookbook.recipes : [];
        var results = [];

        for (var i = 0; i < recipes.length; i++) {
            var r = recipes[i];

            // Source filter
            if (root.cookbookFilter !== "all" && r.source && r.source !== root.cookbookFilter) continue;
            if (root.cookbookFilter === "favorites") {
                var usrState = getUserState(r.repo);
                if (!usrState.favorite) continue;
            }
            if (root.cookbookFilter === "tried") {
                var usrState2 = getUserState(r.repo);
                if (!usrState2.tried) continue;
            }

            // Query filter (client-side search)
            if (root.cookbookQuery && root.cookbookQuery.length > 0) {
                var q = root.cookbookQuery.toLowerCase();
                var name = (r.name || "").toLowerCase();
                var desc = (r.description || "").toLowerCase();
                var repo = (r.repo || "").toLowerCase();
                var family = (r.family || "").toLowerCase();
                if (name.indexOf(q) === -1 && desc.indexOf(q) === -1 && repo.indexOf(q) === -1 && family.indexOf(q) === -1) {
                    continue;
                }
            }

            results.push(r);
        }

        // Sort
        var sort = root.cookbookSort;
        if (sort === "name") {
            results.sort(function (a, b) { return (a.name || "").localeCompare(b.name || ""); });
        } else if (sort === "vram") {
            results.sort(function (a, b) { return (a.estimatedVramGb || 0) - (b.estimatedVramGb || 0); });
        } else if (sort === "rating") {
            results.sort(function (a, b) {
                var ra = getUserState(a.repo).rating || 0;
                var rb = getUserState(b.repo).rating || 0;
                return rb - ra;
            });
        } else if (sort === "fit") {
            // Default: VRAM fit (best fit first, then VRAM ascending)
            var system = cookbook && cookbook.system ? cookbook.system : {};
            var gpu = system.gpu || {};
            var targetVram = system.effectiveVramGb || 8;
            results.sort(function (a, b) {
                var va = a.estimatedVramGb || 0;
                var vb = b.estimatedVramGb || 0;
                var da = Math.abs(va - targetVram);
                var db = Math.abs(vb - targetVram);
                if (da !== db) return da - db;
                return va - vb;
            });
        }

        cookbookResults = results;
        if (results.length > 0) {
            selectedCookbookResult = Math.min(selectedCookbookResult, results.length - 1);
        }
    }

    function onCookbookFilterChanged() {
        selectedCookbookResult = 0;
        applyCookbookFilter();
    }

    function onCookbookQueryChanged() {
        selectedCookbookResult = 0;
        applyCookbookFilter();
    }

    function onCookbookSortChanged() {
        selectedCookbookResult = 0;
        applyCookbookFilter();
    }

    function getVramFitColor(vramGb) {
        if (!vramGb) return root.cDim;
        var system = cookbook && cookbook.system ? cookbook.system : {};
        var gpu = system.gpu || {};
        var targetVram = system.effectiveVramGb || 8;
        var ratio = vramGb / targetVram;
        if (ratio <= 0.7) return root.cGood;
        if (ratio <= 1.2) return root.cWarn;
        return root.cBad;
    }

    function getVramFitText(vramGb) {
        if (!vramGb) return "";
        var system = cookbook && cookbook.system ? cookbook.system : {};
        var gpu = system.gpu || {};
        var targetVram = system.effectiveVramGb || 8;
        var ratio = vramGb / targetVram;
        if (ratio <= 0.7) return "Fit ✓";
        if (ratio <= 1.2) return "Barely";
        return "Too large";
    }

    function getRecipeUserState(repo) {
        var state = getUserState(repo);
        return {
            favorite: state.favorite || false,
            tried: state.tried || false,
            rating: state.rating || 0,
            note: state.note || ""
        };
    }

    function currentCookbookRecipe() {
        var recipes = cookbookResults;
        if (!recipes || recipes.length === 0) return {};
        selectedCookbookResult = Math.max(0, Math.min(selectedCookbookResult, recipes.length - 1));
        return recipes[selectedCookbookResult];
    }

    function searchHuggingFace() {
        browseBusy = true;
        browseStatus = "Searching Hugging Face";
        hfSearchProc.command = ["python3", root.helper, "hf-search", JSON.stringify({ query: root.hfQuery })];
        hfSearchProc.running = false;
        hfSearchProc.running = true;
    }

    function loadHfFiles(repo) {
        if (!repo) return;
        browseBusy = true;
        browseStatus = "Loading model files";
        hfFiles = [];
        selectedHfFile = 0;
        hfFilesProc.command = ["python3", root.helper, "hf-files", JSON.stringify({ repo: repo })];
        hfFilesProc.running = false;
        hfFilesProc.running = true;
    }

    function addLocalModel() {
        let model = currentLocalModel();
        if (!model.path) return;
        browseBusy = true;
        browseStatus = "Adding local model to llama-swap";
        addLocalProc.command = ["python3", root.helper, "add-local", JSON.stringify({
            path: model.path,
            id: model.id || "",
            name: model.name || "",
            description: "Imported local GGUF from " + model.source,
            context: 65536
        })];
        addLocalProc.running = false;
        addLocalProc.running = true;
    }

    function downloadHfModel() {
        let repo = currentHfModel().id || "";
        let file = currentHfFile().name || "";
        if (!repo || !file) return;
        browseBusy = true;
        browseStatus = "Downloading with hf";
        hfDownloadProc.command = ["python3", root.helper, "hf-download", JSON.stringify({
            repo: repo,
            file: file,
            id: file,
            name: file.replace(/\.gguf$/i, ""),
            context: 65536
        })];
        hfDownloadProc.running = false;
        hfDownloadProc.running = true;
    }

    function searchRecipe() {
        let recipe = currentRecipe();
        if (!recipe.query) return;
        hfQuery = recipe.query;
        searchHuggingFace();
    }

    Process {
        id: loadProc
        running: false
        command: ["python3", root.helper, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    let parsed = JSON.parse(this.text);
                    if (parsed.error) {
                        root.statusText = parsed.error;
                    } else {
                        root.state = parsed;
                        root.statusText = "Loaded";
                        root.dirty = false;
                    }
                } catch (e) {
                    root.statusText = "Failed to parse helper output";
                }
            }
        }
    }

    Process {
        id: saveProc
        running: false
        command: ["python3", root.helper, "save", JSON.stringify(root.state)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text);
                    if (parsed.ok) {
                        root.saveText = "Saved. Restart is available when ready.";
                        root.dirty = false;
                        root.runLoad();
                    } else {
                        root.saveText = parsed.error || "Save blocked by validation";
                        if (parsed.validation) root.state.validation = parsed.validation;
                    }
                } catch (e) {
                    root.saveText = "Failed to parse save result";
                }
            }
        }
    }

    Process {
        id: restartProc
        running: false
        command: ["python3", root.helper, "restart"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text);
                    root.saveText = parsed.ok ? "llama-swap restarted" : (parsed.error || "Restart failed");
                    root.runLoad();
                } catch (e) {
                    root.saveText = "Failed to parse restart result";
                }
            }
        }
    }

    Process {
        id: localProc
        running: false
        command: ["python3", root.helper, "local-models"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.browseBusy = false;
                try {
                    let parsed = JSON.parse(this.text);
                    root.localModels = parsed.models || [];
                    root.browseStatus = parsed.ok ? ("Found " + root.localModels.length + " unregistered local models") : (parsed.error || "Local scan failed");
                } catch (e) {
                    root.browseStatus = "Failed to parse local scan result";
                }
            }
        }
    }

    Process {
        id: cookbookProc
        running: false
        command: ["python3", root.helper, "cookbook"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text);
                    if (parsed.ok) {
                        root.cookbook = parsed;
                        root.selectedRecipe = 0;
                        root.loadUserCookbook();
                    } else {
                        root.browseStatus = parsed.error || "Cookbook load failed";
                    }
                } catch (e) {
                    root.browseStatus = "Failed to parse cookbook result";
                }
            }
        }
    }

    Process {
        id: userStateProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // User state CLI commands don't return meaningful state; they modify files directly
            }
        }
    }

    Process {
        id: hfSearchProc
        running: false
        command: ["python3", root.helper, "hf-search", JSON.stringify({ query: root.hfQuery })]
        stdout: StdioCollector {
            onStreamFinished: {
                root.browseBusy = false;
                try {
                    let parsed = JSON.parse(this.text);
                    root.hfResults = parsed.models || [];
                    root.selectedHf = 0;
                    root.hfFiles = [];
                    root.browseStatus = parsed.ok ? ("Found " + root.hfResults.length + " Hugging Face repos") : (parsed.error || "Search failed");
                    if (root.hfResults.length > 0) root.loadHfFiles(root.hfResults[0].id);
                } catch (e) {
                    root.browseStatus = "Failed to parse Hugging Face search result";
                }
            }
        }
    }

    Process {
        id: hfFilesProc
        running: false
        command: ["python3", root.helper, "hf-files", "{}"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.browseBusy = false;
                try {
                    let parsed = JSON.parse(this.text);
                    root.hfFiles = parsed.files || [];
                    root.selectedHfFile = 0;
                    root.browseStatus = parsed.ok ? ("Found " + root.hfFiles.length + " GGUF files") : (parsed.error || "File load failed");
                } catch (e) {
                    root.browseStatus = "Failed to parse Hugging Face file result";
                }
            }
        }
    }

    Process {
        id: addLocalProc
        running: false
        command: ["python3", root.helper, "add-local", "{}"]
        stdout: StdioCollector {
            onStreamFinished: root.handleModelAddResult(this.text)
        }
    }

    Process {
        id: hfDownloadProc
        running: false
        command: ["python3", root.helper, "hf-download", "{}"]
        stdout: StdioCollector {
            onStreamFinished: root.handleModelAddResult(this.text)
        }
    }

    function handleModelAddResult(text) {
        root.browseBusy = false;
        try {
            let parsed = JSON.parse(text);
            if (parsed.ok) {
                root.browseStatus = "Added " + parsed.model + " to llama-swap router";
                root.runLoad();
                root.loadLocalModels();
            } else {
                root.browseStatus = parsed.error || "Model add failed";
            }
        } catch (e) {
            root.browseStatus = "Failed to parse model add result";
        }
    }

    Component.onCompleted: {
        runLoad();
        loadCookbook();
        loadLocalModels();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closePanel()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.025, 0.035, 0.58)
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 1180)
        height: Math.min(parent.height - 64, 1050)
        radius: 8
        color: root.cBg
        border.color: root.cBorder
        border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Local LLM Manager"
                    color: root.cFg
                    font.pixelSize: 22
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    text: root.dirty ? "Unsaved" : root.statusText
                    color: root.dirty ? root.cWarn : root.cDim
                    font.pixelSize: 12
                }
                Button {
                    label: "Reload"
                    onClicked: root.runLoad()
                }
                Button {
                    label: "Save"
                    active: root.dirty
                    onClicked: {
                        root.saveText = "Saving";
                        saveProc.command = ["python3", root.helper, "save", JSON.stringify(root.state)];
                        saveProc.running = false;
                        saveProc.running = true;
                    }
                }
                Button {
                    label: "Restart"
                    active: !root.dirty
                    onClicked: {
                        root.saveText = "Restarting";
                        restartProc.running = false;
                        restartProc.running = true;
                    }
                }
                Button {
                    label: "Close"
                    onClicked: root.closePanel()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: ["Runtime", "Models", "Browse", "Agents", "Defaults", "Validation"]
                    Pill {
                        label: modelData
                        active: root.tab === index
                        onClicked: root.tab = index
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.cPanel2 }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.tab === 0 ? runtimeTab
                    : root.tab === 1 ? modelsTab
                    : root.tab === 2 ? browseTab
                    : root.tab === 3 ? agentsTab
                    : root.tab === 4 ? defaultsTab
                    : validationTab
            }

            Text {
                Layout.fillWidth: true
                text: root.saveText
                color: root.saveText.indexOf("failed") >= 0 || root.saveText.indexOf("blocked") >= 0 ? root.cBad : root.cDim
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: runtimeTab
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            InfoRow { label: "Router"; value: root.state.runtime && root.state.runtime.router ? "online" : "offline"; good: !!(root.state.runtime && root.state.runtime.router) }
            InfoRow { label: "Backend"; value: root.state.runtime && root.state.runtime.backend ? "online" : "offline"; good: !!(root.state.runtime && root.state.runtime.backend) }
            TextBlock {
                title: "GPU"
                text: root.state.runtime && root.state.runtime.gpu ? root.state.runtime.gpu.text : ""
            }
            TextBlock {
                title: "Running Models"
                text: (root.state.runtime && root.state.runtime.running && root.state.runtime.running.length > 0)
                    ? root.state.runtime.running.map(function(m) { return (m.model || "") + "  " + (m.state || ""); }).join("\n")
                    : "(none)"
            }
        }
    }

    Component {
        id: modelsTab
        RowLayout {
            anchors.fill: parent
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 330
                Layout.minimumWidth: 330
                Layout.maximumWidth: 330
                Layout.fillHeight: true
                color: root.cPanel
                radius: 8
                ListColumn {
                    items: root.modelList()
                    selected: root.selectedModel
                    labelKey: "id"
                    subKey: "name"
                    onPicked: function(i) { root.selectedModel = i; }
                }
            }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: modelForm.implicitHeight
                clip: true
                ColumnLayout {
                    id: modelForm
                    width: parent.width
                    spacing: 10
                    Field { label: "ID"; value: root.currentModel().id || ""; readOnly: true }
                    Field { label: "Name"; value: root.currentModel().name || ""; onCommitted: function(v) { root.setModelField("name", v); } }
                    Field { label: "Description"; value: root.currentModel().description || ""; onCommitted: function(v) { root.setModelField("description", v); } }
                    Field { label: "TTL seconds"; value: String(root.currentModel().ttl || ""); onCommitted: function(v) { root.setModelField("ttl", v); } }
                    Field { label: "Model file"; value: root.currentModel().path || ""; readOnly: true }
                    InfoRow { label: "Context"; value: String(root.currentModel().context || "unknown"); good: true }
                    InfoRow { label: "Output"; value: String(root.currentModel().output || "unknown"); good: true }
                    InfoRow { label: "Vision"; value: root.currentModel().vision ? "yes" : "no"; good: !!root.currentModel().vision }
                    InfoRow { label: "CPU Shadow"; value: root.currentModel().cpu ? "yes" : "no"; good: !root.currentModel().cpu }
                    MultiField {
                        label: "Aliases"
                        value: root.refListText(root.currentModel().aliases || [])
                        readOnly: true
                    }
                    MultiField {
                        label: "llama-server command"
                        value: root.currentModel().cmd || ""
                        onCommitted: function(v) { root.setModelField("cmd", v); }
                    }

                }
            }
        }
    }

    Component {
        id: browseTab
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Section { text: "Browse for new models" }
            InfoRow { label: "Status"; value: root.browseBusy ? root.browseStatus + "..." : root.browseStatus; good: !root.browseBusy }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: Math.max(500, card.width * 0.48)
                    Layout.minimumWidth: 460
                    Layout.fillHeight: true
                    color: root.cPanel
                    radius: 8
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Section { text: "Cookbook" }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.systemSummary()
                                    color: root.cDim
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                            Button {
                                label: "Refresh"
                                onClicked: root.loadCookbook()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10
                            ColumnLayout {
                                Layout.preferredWidth: 300
                                Layout.fillHeight: true
                                spacing: 6
                                Field {
                                    Layout.fillWidth: true
                                    label: "Search"
                                    value: root.cookbookQuery
                                    onCommitted: function(v) { root.cookbookQuery = v; root.onCookbookQueryChanged(); }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: ["all", "favorites", "tried", "curated", "hf"]
                                        delegate: Pill {
                                            label: modelData === "all" ? "All" : (modelData === "favorites" ? "★" : (modelData === "tried" ? "✓" : (modelData === "curated" ? "Curated" : "HF")))
                                            active: root.cookbookFilter === modelData
                                            onClicked: { root.cookbookFilter = modelData; root.onCookbookFilterChanged(); }
                                        }
                                    }
                                    ComboBox {
                                        Layout.preferredWidth: 100
                                        model: ["fit", "name", "vram", "rating"]
                                        textRole: "modelData"
                                        currentIndex: ["fit", "name", "vram", "rating"].indexOf(root.cookbookSort)
                                        onActivated: function(idx) { root.cookbookSort = ["fit", "name", "vram", "rating"][idx]; root.onCookbookSortChanged(); }
                                        label: "Sort"
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: root.cBg
                                    radius: 6
                                    ListColumn {
                                        items: root.cookbookResults
                                        selected: root.selectedCookbookResult
                                        labelKey: "title"
                                        subKey: "repo"
                                        subKey2: "date"
                                        onPicked: function(i) { root.selectedCookbookResult = i; }
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.currentCookbookRecipe().title || ""
                                            color: root.cFg
                                            font.pixelSize: 18
                                            font.bold: true
                                            wrapMode: Text.Wrap
                                        }
                                        // Favorites star
                                        Text {
                                            text: "★"
                                            color: getRecipeUserState(root.currentCookbookRecipe().repo).favorite ? "#eb9e3c" : root.cDim
                                            font.pixelSize: 18
                                            cursorShape: Qt.PointingHandCursor
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: root.toggleFavorite(root.currentCookbookRecipe().repo)
                                            }
                                        }
                                    }
                                    // Rating stars
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Repeater {
                                            model: 5
                                            Text {
                                                text: "★"
                                                color: (getRecipeUserState(root.currentCookbookRecipe().repo).rating || 0) >= modelData ? "#eb9e3c" : root.cDim
                                                font.pixelSize: 14
                                                cursorShape: Qt.PointingHandCursor
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: root.setRating(root.currentCookbookRecipe().repo, modelData + 1)
                                                }
                                            }
                                        }
                                        Text {
                                            text: getRecipeUserState(root.currentCookbookRecipe().repo).tried ? "✓ Tried" : ""
                                            color: getRecipeUserState(root.currentCookbookRecipe().repo).tried ? root.cGood : "transparent"
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                                InfoRow { label: "Repo"; value: root.currentCookbookRecipe().repo || ""; good: true }
                                InfoRow { label: "Source"; value: root.currentCookbookRecipe().source || ""; good: true }
                                InfoRow { label: "Quant"; value: root.currentCookbookRecipe().quant || ""; good: true }
                                InfoRow { label: "Context"; value: root.currentCookbookRecipe().context || ""; good: true }
                                // VRAM fit with color
                                TextBlock {
                                    title: "VRAM Fit"
                                    text: root.getVramFitText(root.currentCookbookRecipe().estimatedVramGb) + " (" + (root.currentCookbookRecipe().estimatedVramGb || "?") + " GB)"
                                    textColor: root.getVramFitColor(root.currentCookbookRecipe().estimatedVramGb)
                                }
                                TextBlock {
                                    title: "Use Case"
                                    text: root.currentCookbookRecipe().why || ""
                                }
                                TextBlock {
                                    title: "Personal Note"
                                    text: getRecipeUserState(root.currentCookbookRecipe().repo).note || "(add a note)"
                                    color: getRecipeUserState(root.currentCookbookRecipe().repo).note ? root.cFg : root.cDim
                                }
                                Button {
                                    label: "Search recipe"
                                    Layout.fillWidth: true
                                    active: (root.currentCookbookRecipe().query || "") !== "" && !root.browseBusy
                                    onClicked: root.searchRecipe()
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.cPanel
                        radius: 8
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Section { text: "Hugging Face GGUF" }
                            RowLayout {
                                Layout.fillWidth: true
                                Field {
                                    label: "Search"
                                    value: root.hfQuery
                                    onCommitted: function(v) { root.hfQuery = v; }
                                    Layout.fillWidth: true
                                }
                                Button {
                                    label: "Search"
                                    active: !root.browseBusy
                                    onClicked: root.searchHuggingFace()
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: root.cBg
                                    radius: 6
                                    ListColumn {
                                        items: root.hfResults
                                        selected: root.selectedHf
                                        labelKey: "id"
                                        subKey: "downloads"
                                        subKey2: "lastModified"
                                        onPicked: function(i) {
                                            root.selectedHf = i;
                                            root.loadHfFiles(root.currentHfModel().id || "");
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 6
                                    InfoRow { label: "Repo"; value: root.currentHfModel().id || ""; good: true }
                                    InfoRow { label: "Downloads"; value: String(root.currentHfModel().downloads || 0); good: true }
                                    InfoRow { label: "Likes"; value: String(root.currentHfModel().likes || 0); good: true }
                                    InfoRow { label: "Updated"; value: root.currentHfModel().lastModified || ""; good: true }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: root.cBg
                                        radius: 6
                                        ListColumn {
                                            items: root.hfFiles
                                            selected: root.selectedHfFile
                                            labelKey: "name"
                                            subKey: "sizeText"
                                            onPicked: function(i) { root.selectedHfFile = i; }
                                        }
                                    }
                                    Button {
                                        label: "Download and add"
                                        Layout.fillWidth: true
                                        active: !root.browseBusy && (root.currentHfFile().name || "") !== ""
                                        onClicked: root.downloadHfModel()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.cPanel
                        radius: 8
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Section { text: "Local GGUF not in router"; Layout.fillWidth: true }
                                Button {
                                    label: "Scan"
                                    active: !root.browseBusy
                                    onClicked: root.loadLocalModels()
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: root.cBg
                                    radius: 6
                                    ListColumn {
                                        items: root.localModels
                                        selected: root.selectedLocal
                                        labelKey: "name"
                                        subKey: "sizeText"
                                        onPicked: function(i) { root.selectedLocal = i; }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 6
                                    InfoRow { label: "Suggested ID"; value: root.currentLocalModel().id || ""; good: true }
                                    InfoRow { label: "Size"; value: root.currentLocalModel().sizeText || ""; good: true }
                                    InfoRow { label: "Source"; value: root.currentLocalModel().source || ""; good: true }
                                    MultiField {
                                        label: "Path"
                                        value: root.currentLocalModel().path || ""
                                        readOnly: true
                                    }
                                    Button {
                                        label: "Add to router"
                                        Layout.fillWidth: true
                                        active: !root.browseBusy && (root.currentLocalModel().path || "") !== ""
                                        onClicked: root.addLocalModel()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: agentsTab
        RowLayout {
            anchors.fill: parent
            spacing: 12
            ColumnLayout {
                Layout.preferredWidth: 360
                Layout.minimumWidth: 360
                Layout.maximumWidth: 360
                Layout.fillHeight: true
                RowLayout {
                    Layout.fillWidth: true
                    Pill { label: "opencode"; active: root.agentSystem === "opencode"; onClicked: { root.agentSystem = "opencode"; root.selectedAgent = 0; } }
                    Pill { label: "pi"; active: root.agentSystem === "pi"; onClicked: { root.agentSystem = "pi"; root.selectedAgent = 0; } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.cPanel
                    radius: 8
                    ListColumn {
                        items: root.agentList()
                        selected: root.selectedAgent
                        labelKey: "id"
                        subKey: "model"
                        onPicked: function(i) { root.selectedAgent = i; }
                    }
                }
                Button {
                    label: "Add subagent"
                    Layout.fillWidth: true
                    onClicked: root.addAgent()
                }
            }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 360
                contentWidth: width
                contentHeight: agentForm.implicitHeight
                clip: true
                ColumnLayout {
                    id: agentForm
                    width: parent.width
                    spacing: 10
                    Field { label: "Name"; value: root.currentAgent().id || ""; onCommitted: function(v) { root.setAgentField("id", v); } }
                    Field { label: "Description"; value: root.currentAgent().description || ""; onCommitted: function(v) { root.setAgentField("description", v); } }
                    Dropdown {
                        label: "Model"
                        value: root.currentAgent().model || ""
                        options: root.modelRefOptions(root.currentAgent().model || "")
                        onSelected: function(v) { root.setAgentField("model", v); }
                    }
                    Dropdown {
                        label: "Mode"
                        value: root.currentAgent().mode || ""
                        options: root.agentModeOptions(root.currentAgent().mode || "")
                        onSelected: function(v) { root.setAgentField("mode", v); }
                    }
                    MultiField {
                        label: "Prompt"
                        value: root.currentAgent().body || ""
                        onCommitted: function(v) { root.setAgentField("body", v); }
                    }
                }
            }
        }
    }

    Component {
        id: defaultsTab
        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: defaultsCol.implicitHeight
            clip: true
            ColumnLayout {
                id: defaultsCol
                width: parent.width
                spacing: 12
                Section { text: "opencode" }
                Dropdown {
                    label: "Primary model"
                    value: root.state.opencode ? root.state.opencode.model || "" : ""
                    options: root.modelRefOptions(root.state.opencode ? root.state.opencode.model || "" : "")
                    onSelected: function(v) { root.state.opencode.model = v; root.dirty = true; }
                }
                Dropdown {
                    label: "Small model"
                    value: root.state.opencode ? root.state.opencode.small_model || "" : ""
                    options: root.modelRefOptions(root.state.opencode ? root.state.opencode.small_model || "" : "")
                    onSelected: function(v) { root.state.opencode.small_model = v; root.dirty = true; }
                }
                Dropdown {
                    label: "Default agent"
                    value: root.state.opencode ? root.state.opencode.default_agent || "" : ""
                    options: root.defaultAgentOptions(root.state.opencode ? root.state.opencode.default_agent || "" : "")
                    onSelected: function(v) { root.state.opencode.default_agent = v; root.dirty = true; }
                }
                Section { text: "pi" }
                Dropdown {
                    label: "Default provider"
                    value: root.state.pi ? root.state.pi.defaultProvider || "" : ""
                    options: root.providerOptions(root.state.pi ? root.state.pi.defaultProvider || "" : "")
                    onSelected: function(v) { root.state.pi.defaultProvider = v; root.dirty = true; }
                }
                Dropdown {
                    label: "Default model"
                    value: root.state.pi ? root.state.pi.defaultModel || "" : ""
                    options: root.rawModelOptions(root.state.pi ? root.state.pi.defaultModel || "" : "")
                    onSelected: function(v) { root.state.pi.defaultModel = v; root.dirty = true; }
                }
                Dropdown {
                    label: "Thinking level"
                    value: root.state.pi ? root.state.pi.defaultThinkingLevel || "" : ""
                    options: root.thinkingOptions(root.state.pi ? root.state.pi.defaultThinkingLevel || "" : "")
                    onSelected: function(v) { root.state.pi.defaultThinkingLevel = v; root.dirty = true; }
                }
                MultiField {
                    label: "Enabled pi models"
                    value: root.refListText(root.state.pi ? root.state.pi.enabledModels : [])
                    onCommitted: function(v) { root.state.pi.enabledModels = root.refsFromText(v); root.dirty = true; }
                }
            }
        }
    }

    Component {
        id: validationTab
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            TextBlock {
                title: "Errors"
                text: root.state.validation && root.state.validation.errors && root.state.validation.errors.length > 0
                    ? root.state.validation.errors.join("\n")
                    : "(none)"
                bad: root.state.validation && root.state.validation.errors && root.state.validation.errors.length > 0
            }
            TextBlock {
                title: "Warnings"
                text: root.state.validation && root.state.validation.warnings && root.state.validation.warnings.length > 0
                    ? root.state.validation.warnings.join("\n")
                    : "(none)"
            }
            TextBlock {
                title: "Managed paths"
                text: root.state.paths ? Object.keys(root.state.paths).map(function(k) { return k + ": " + root.state.paths[k]; }).join("\n") : ""
            }
        }
    }

    component ListColumn: Flickable {
        id: listRoot
        property var items: []
        property int selected: 0
        property string labelKey: "id"
        property string subKey: ""
        property string subKey2: ""
        signal picked(int index)
        anchors.fill: parent
        anchors.margins: 8
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true
        Column {
            id: listCol
            width: parent.width
            spacing: 4
            Repeater {
                model: listRoot.items || []
                Rectangle {
                    width: listCol.width
                    height: listRoot.subKey2 ? 58 : 48
                    radius: 6
                    color: index === listRoot.selected ? root.cPanel2 : (ma.containsMouse ? Qt.lighter(root.cPanel, 1.15) : "transparent")
                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        Text { text: modelData[listRoot.labelKey] || ""; color: root.cFg; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                        Text { text: listRoot.subKey ? (modelData[listRoot.subKey] || "") : ""; color: root.cDim; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width; visible: listRoot.subKey !== "" }
                        Text { text: listRoot.subKey2 ? (root.formatDate(modelData[listRoot.subKey2]) || "") : ""; color: root.cDim; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width; visible: listRoot.subKey2 !== "" }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: listRoot.picked(index)
                    }
                }
            }
        }
    }

    component Section: Text {
        Layout.fillWidth: true
        color: root.cAccent
        font.bold: true
        font.pixelSize: 15
    }

    component Button: Rectangle {
        property string label: ""
        property bool active: true
        signal clicked()
        Layout.preferredWidth: Math.max(72, labelText.implicitWidth + 22)
        Layout.preferredHeight: 32
        radius: 6
        opacity: active ? 1.0 : 0.55
        color: ma.containsMouse ? Qt.lighter(root.cPanel2, 1.2) : root.cPanel2
        border.color: root.cBorder
        Text { id: labelText; anchors.centerIn: parent; text: label; color: root.cFg; font.pixelSize: 12 }
        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: parent.active
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component Pill: Rectangle {
        property string label: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 6
        color: active ? root.cAccent : (ma.containsMouse ? Qt.lighter(root.cPanel2, 1.2) : root.cPanel2)
        Text { anchors.centerIn: parent; text: label; color: active ? root.cBg : root.cFg; font.pixelSize: 12; font.bold: active }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component ComboBox: ColumnLayout {
        id: comboRoot
        property string label: ""
        property var model: []
        property string textRole: "modelData"
        property int currentIndex: 0
        property string currentText: currentIndex >= 0 && currentIndex < model.length ? String(model[currentIndex]) : ""
        signal activated(int index)
        Layout.preferredHeight: 32
        spacing: 0
        Text {
            Layout.fillWidth: true
            text: comboRoot.label
            color: root.cDim
            font.pixelSize: 11
            visible: comboRoot.label !== ""
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: ma.containsMouse ? Qt.lighter(root.cPanel2, 1.2) : root.cPanel2
            border.color: root.cBorder
            Text {
                anchors.centerIn: parent
                text: comboRoot.currentText
                color: root.cFg
                font.pixelSize: 12
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: comboRoot.clicked()
            }
        }
        function clicked() {
            // Simple toggle: cycle through options
            var nextIndex = (comboRoot.currentIndex + 1) % comboRoot.model.length;
            comboRoot.currentIndex = nextIndex;
            comboRoot.activated(nextIndex);
        }
    }

    component InfoRow: RowLayout {
        property string label: ""
        property string value: ""
        property bool good: false
        Layout.fillWidth: true
        Text { text: parent.label; color: root.cDim; font.pixelSize: 13; Layout.preferredWidth: 150 }
        Text { text: parent.value; color: parent.good ? root.cGood : root.cFg; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }

    component Field: ColumnLayout {
        id: fieldRoot
        property string label: ""
        property string value: ""
        property bool readOnly: false
        signal committed(string value)
        Layout.fillWidth: true
        spacing: 4
        Text { text: fieldRoot.label; color: root.cDim; font.pixelSize: 12 }
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 6
            color: root.cPanel
            border.color: root.cPanel2
            TextInput {
                id: input
                anchors.fill: parent
                anchors.margins: 8
                text: fieldRoot.value
                readOnly: fieldRoot.readOnly
                color: fieldRoot.readOnly ? root.cDim : root.cFg
                selectionColor: root.cBorder
                font.pixelSize: 13
                clip: true
                onEditingFinished: fieldRoot.committed(text)
            }
        }
    }

    component Dropdown: ColumnLayout {
        id: dropdownRoot
        property string label: ""
        property string value: ""
        property var options: []
        property bool open: false
        signal selected(string value)
        Layout.fillWidth: true
        spacing: 4

        Text { text: dropdownRoot.label; color: root.cDim; font.pixelSize: 12 }

        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 6
            color: dropdownMouse.containsMouse ? Qt.lighter(root.cPanel, 1.08) : root.cPanel
            border.color: dropdownRoot.open ? root.cBorder : root.cPanel2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8
                Text {
                    text: dropdownRoot.value === "" ? "(none)" : dropdownRoot.value
                    color: dropdownRoot.value === "" ? root.cDim : root.cFg
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: dropdownRoot.open ? "^" : "v"
                    color: root.cDim
                    font.pixelSize: 10
                }
            }
            MouseArea {
                id: dropdownMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dropdownRoot.open = !dropdownRoot.open
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: dropdownRoot.open ? Math.min(260, Math.max(34, optionCol.implicitHeight + 8)) : 0
            visible: dropdownRoot.open
            radius: 6
            color: root.cPanel
            border.color: root.cPanel2
            clip: true
            Flickable {
                anchors.fill: parent
                anchors.margins: 4
                contentWidth: width
                contentHeight: optionCol.implicitHeight
                clip: true
                Column {
                    id: optionCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: dropdownRoot.options || []
                        Rectangle {
                            width: optionCol.width
                            height: 30
                            radius: 4
                            color: modelData === dropdownRoot.value
                                ? root.cAccent
                                : (optionMouse.containsMouse ? Qt.lighter(root.cPanel2, 1.18) : "transparent")
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: String(modelData) === "" ? "(none)" : String(modelData)
                                color: modelData === dropdownRoot.value ? root.cBg : root.cFg
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: optionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dropdownRoot.open = false;
                                    dropdownRoot.selected(String(modelData));
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component MultiField: ColumnLayout {
        id: multiRoot
        property string label: ""
        property string value: ""
        property bool readOnly: false
        signal committed(string value)
        Layout.fillWidth: true
        spacing: 4
        Text { text: multiRoot.label; color: root.cDim; font.pixelSize: 12 }
        Rectangle {
            Layout.fillWidth: true
            height: Math.max(130, Math.min(360, edit.contentHeight + 24))
            radius: 6
            color: root.cPanel
            border.color: root.cPanel2
            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                contentWidth: width
                contentHeight: edit.contentHeight
                clip: true
                TextEdit {
                    id: edit
                    width: parent.width
                    text: multiRoot.value
                    readOnly: multiRoot.readOnly
                    color: multiRoot.readOnly ? root.cDim : root.cFg
                    selectionColor: root.cBorder
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: TextEdit.Wrap
                    onActiveFocusChanged: if (!activeFocus) multiRoot.committed(text)
                }
            }
        }
    }

    component TextBlock: ColumnLayout {
        property string title: ""
        property string text: ""
        property bool bad: false
        property color textColor: root.cFg
        Layout.fillWidth: true
        spacing: 4
        Text { text: parent.title; color: parent.bad ? root.cBad : root.cAccent; font.bold: true; font.pixelSize: 14 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(84, Math.min(240, body.implicitHeight + 22))
            color: root.cPanel
            radius: 8
            Text {
                id: body
                anchors.fill: parent
                anchors.margins: 10
                text: parent.parent.text
                color: parent.parent.textColor
                font.family: "monospace"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }
}
