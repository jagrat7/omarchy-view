import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../services"
import "."

Scope {
    id: overviewScope
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    readonly property var appLibrary: shell ? shell.appLibrary : null
    property var manifest: null
    property var settings: ({})
    property bool opened: GlobalStates.overviewOpen
    property string selectedWindowAddress: ""
    property int selectedWorkspaceId: 0
    property bool workspaceSelectionActive: false
    property bool windowSwitching: false
    property var heldSwitchKeys: ({})
    property bool sawSwitchKeyEvent: false
    property bool switchModifiersHeld: false
    property string pendingWindowAddress: ""

    // Read a single value from this plugin's inline shell.json entry, with a
    // fallback for missing/null values. Matches Omarchy Panel.setting().
    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function entrySettings() {
        const id = String(manifest?.id || "omarchy-overview");
        const config = shell?.shellConfig || null;
        const plugins = config?.plugins || [];
        if (!Array.isArray(plugins))
            return settings || ({});

        for (const entry of plugins) {
            if (String(entry?.id || "") === id)
                return entry;
        }
        return settings || ({});
    }

    function syncSettings() {
        const next = entrySettings() || ({});
        settings = next;
        Config.settings = next;
    }

    function normalizedAddress(address) {
        const value = `${address ?? ""}`.trim();
        if (value.length === 0)
            return "";
        return value.startsWith("0x") ? value : `0x${value}`;
    }

    function windowCandidates() {
        const workspacesPerGroup = Config.options.overview.rows * Config.options.overview.columns;
        const currentId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
        const useWorkspaceMap = Config.options.overview.useWorkspaceMap;
        const workspaceMap = Config.options.overview.workspaceMap ?? [];
        const focusedMonitorId = Hyprland.focusedMonitor?.id ?? 0;
        const workspaceOffset = useWorkspaceMap ? Number(workspaceMap[focusedMonitorId] ?? 0) : 0;
        const currentGroup = Math.floor((currentId - workspaceOffset - 1) / workspacesPerGroup);
        const minWorkspaceId = currentGroup * workspacesPerGroup + 1 + workspaceOffset;
        const maxWorkspaceId = minWorkspaceId + workspacesPerGroup - 1;

        const renderedAddresses = new Set();
        for (const toplevel of (ToplevelManager.toplevels.values ?? []))
            renderedAddresses.add(normalizedAddress(toplevel?.HyprlandToplevel?.address));

        return (HyprlandData.windowList ?? []).filter(windowData => {
            const address = normalizedAddress(windowData?.address);
            if (address.length === 0 || !renderedAddresses.has(address))
                return false;
            if (windowData?.mapped === false || windowData?.hidden === true)
                return false;

            const workspaceName = `${windowData?.workspace?.name ?? ""}`;
            if (workspaceName.startsWith("special:")) {
                return Config.options.overview.showSpecialWorkspaces
                    && (windowData?.monitor ?? -1) === focusedMonitorId;
            }

            const workspaceId = Number(windowData?.workspace?.id);
            return Number.isFinite(workspaceId)
                && workspaceId >= minWorkspaceId
                && workspaceId <= maxWorkspaceId;
        }).sort((left, right) => {
            const leftHistory = Number(left?.focusHistoryID);
            const rightHistory = Number(right?.focusHistoryID);
            const leftRank = Number.isFinite(leftHistory) && leftHistory >= 0 ? leftHistory : Number.MAX_SAFE_INTEGER;
            const rightRank = Number.isFinite(rightHistory) && rightHistory >= 0 ? rightHistory : Number.MAX_SAFE_INTEGER;
            if (leftRank !== rightRank)
                return leftRank - rightRank;
            return normalizedAddress(left?.address).localeCompare(normalizedAddress(right?.address));
        });
    }

    function selectCurrentWindow() {
        const candidates = windowCandidates();
        const currentWindow = candidates.length > 0 ? candidates[0] : null;
        selectedWindowAddress = currentWindow ? normalizedAddress(currentWindow.address) : "";
        selectedWorkspaceId = Number(currentWindow?.workspace?.id) || 0;
        workspaceSelectionActive = false;
    }

    function selectWorkspaceWindow(workspaceId) {
        selectedWorkspaceId = workspaceId;
        workspaceSelectionActive = true;
        const candidates = windowCandidates();
        const workspaceWindow = candidates.find(windowData =>
            Number(windowData?.workspace?.id) === workspaceId);
        selectedWindowAddress = workspaceWindow ? normalizedAddress(workspaceWindow.address) : "";
    }

    function heldSwitchKeysEmpty() {
        for (const key in heldSwitchKeys)
            return false;
        return true;
    }

    function resetSwitchKeyState() {
        heldSwitchKeys = ({});
        sawSwitchKeyEvent = false;
        switchModifiersHeld = false;
    }

    function setSwitchKeyHeld(key, held) {
        const next = Object.assign({}, heldSwitchKeys);
        if (held)
            next[key] = true;
        else
            delete next[key];
        heldSwitchKeys = next;
    }

    function noteSwitchKeyPressed(event) {
        sawSwitchKeyEvent = true;
        switchModifiersHeld = !!(event.modifiers
            & (Qt.AltModifier | Qt.MetaModifier | Qt.ControlModifier));
        setSwitchKeyHeld(event.key, true);
    }

    function noteSwitchKeyReleased(event) {
        sawSwitchKeyEvent = true;
        setSwitchKeyHeld(event.key, false);

        // Qt may still report the modifier that is currently being released.
        const altReleasing = event.key === Qt.Key_Alt;
        const superReleasing = event.key === Qt.Key_Meta
            || event.key === Qt.Key_Super_L
            || event.key === Qt.Key_Super_R;
        const controlReleasing = event.key === Qt.Key_Control;
        const altHeld = (event.modifiers & Qt.AltModifier) && !altReleasing;
        const superHeld = (event.modifiers & Qt.MetaModifier) && !superReleasing;
        const controlHeld = (event.modifiers & Qt.ControlModifier) && !controlReleasing;
        switchModifiersHeld = !!(altHeld || superHeld || controlHeld);
    }

    function cycleWindow(delta) {
        const candidates = windowCandidates();
        workspaceSelectionActive = false;
        if (candidates.length === 0) {
            selectedWindowAddress = "";
            selectedWorkspaceId = 0;
            return;
        }

        const step = delta < 0 ? -1 : 1;
        let currentIndex = candidates.findIndex(windowData =>
            normalizedAddress(windowData?.address) === selectedWindowAddress);
        if (currentIndex < 0)
            currentIndex = step > 0 ? -1 : 0;

        const nextIndex = (currentIndex + step + candidates.length) % candidates.length;
        const nextWindow = candidates[nextIndex];
        selectedWindowAddress = normalizedAddress(nextWindow.address);
        selectedWorkspaceId = Number(nextWindow?.workspace?.id) || 0;
    }

    function startWindowSwitch(delta) {
        selectedWindowFocusTimer.stop();
        pendingWindowAddress = "";
        resetSwitchKeyState();
        windowSwitching = true;
        selectCurrentWindow();
        cycleWindow(delta);
        GlobalStates.overviewOpen = true;
        modifierFallbackTimer.restart();
    }

    function advanceWindowSwitch(delta) {
        if (GlobalStates.overviewOpen) {
            // If the compositor shortcut refires, its modifier is still held.
            windowSwitching = true;
            sawSwitchKeyEvent = true;
            switchModifiersHeld = true;
            cycleWindow(delta);
        } else {
            startWindowSwitch(delta);
        }
    }

    function activateSelectedWindow() {
        const address = selectedWindowAddress;
        const windowData = HyprlandData.windowByAddress[address];
        modifierFallbackTimer.stop();
        GlobalStates.overviewOpen = false;

        if (!windowData)
            return;
        pendingWindowAddress = address;
        selectedWindowFocusTimer.restart();
    }

    function cancelWindowSwitch() {
        modifierFallbackTimer.stop();
        selectedWindowFocusTimer.stop();
        pendingWindowAddress = "";
        GlobalStates.overviewOpen = false;
    }

    onManifestChanged: syncSettings()
    onShellChanged: syncSettings()
    onOpenedChanged: {
        if (!opened) {
            selectedWindowAddress = "";
            selectedWorkspaceId = 0;
            workspaceSelectionActive = false;
            windowSwitching = false;
            resetSwitchKeyState();
        }
    }
    Component.onCompleted: syncSettings()

    Connections {
        target: overviewScope.shell
        ignoreUnknownSignals: true
        function onShellConfigChanged() {
            overviewScope.syncSettings();
        }
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            if (!GlobalStates.overviewOpen)
                return;

            const candidates = overviewScope.windowCandidates();
            const selectionStillExists = candidates.some(windowData =>
                overviewScope.normalizedAddress(windowData?.address) === overviewScope.selectedWindowAddress
                    && (!overviewScope.workspaceSelectionActive
                        || Number(windowData?.workspace?.id) === overviewScope.selectedWorkspaceId));
            if (selectionStillExists)
                return;

            // An empty selection is intentional after navigating to an empty
            // workspace. Do not replace it with an unrelated MRU window when
            // Hyprland refreshes the client list after the workspace switch.
            if (overviewScope.workspaceSelectionActive) {
                if (overviewScope.selectedWindowAddress.length > 0)
                    overviewScope.selectWorkspaceWindow(overviewScope.selectedWorkspaceId);
                return;
            }

            overviewScope.selectCurrentWindow();
            if (overviewScope.windowSwitching)
                overviewScope.cycleWindow(1);
        }
    }

    function open(payloadJson) {
        modifierFallbackTimer.stop();
        selectedWindowFocusTimer.stop();
        pendingWindowAddress = "";
        resetSwitchKeyState();
        windowSwitching = false;
        selectCurrentWindow();
        GlobalStates.overviewOpen = true;
    }

    function close() {
        cancelWindowSwitch();
    }

    function toggle(payloadJson) {
        advanceWindowSwitch(1);
    }

    Timer {
        id: modifierFallbackTimer
        interval: 150
        repeat: true
        onTriggered: {
            if (!GlobalStates.overviewOpen || !overviewScope.windowSwitching) {
                stop();
                return;
            }

            // Qt can omit the still-held compositor modifier from a Tab
            // release event. Never commit from event.modifiers alone: ask
            // Hyprland for the physical key state whenever no ordinary key
            // is currently held.
            if (!overviewScope.heldSwitchKeysEmpty())
                return;

            if (!modifierStateCheck.running)
                modifierStateCheck.running = true;
        }
    }

    Process {
        id: modifierStateCheck
        command: [
            "hyprctl", "eval",
            "error(tostring(hl.is_key_down(\"Alt_L\") or hl.is_key_down(\"Alt_R\") or hl.is_key_down(\"Super_L\") or hl.is_key_down(\"Super_R\") or hl.is_key_down(\"Control_L\") or hl.is_key_down(\"Control_R\")))"
        ]
        stdout: StdioCollector {
            id: modifierStateCollector
            onStreamFinished: {
                if (!GlobalStates.overviewOpen
                        || !overviewScope.windowSwitching
                        || !overviewScope.heldSwitchKeysEmpty())
                    return;

                const match = modifierStateCollector.text.trim().match(/(?:^|[\s:])(true|false)$/);
                if (!match)
                    return;

                if (match[1] === "false")
                    overviewScope.activateSelectedWindow();
            }
        }
    }

    Timer {
        id: selectedWindowFocusTimer
        interval: 100
        repeat: false
        onTriggered: {
            const address = overviewScope.pendingWindowAddress;
            overviewScope.pendingWindowAddress = "";
            if (address.length === 0)
                return;

            if (Hyprland.usingLua) {
                Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${address}' })`);
            } else {
                Hyprland.dispatch(`focuswindow address:${address}`);
            }
        }
    }

    GlobalShortcut {
        appid: "omarchy-overview"
        name: "next"
        onPressed: overviewScope.advanceWindowSwitch(1)
    }

    GlobalShortcut {
        appid: "omarchy-overview"
        name: "previous"
        onPressed: overviewScope.advanceWindowSwitch(-1)
    }

    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            readonly property var shell: overviewScope.shell
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            property bool blurEnabled: Config.options.overview.effects.enableBlur
            property bool closeOnFocusLoss: Config.options.overview.closeOnFocusLoss ?? true
            screen: modelData
            visible: GlobalStates.overviewOpen

            WlrLayershell.namespace: blurEnabled ? "quickshell:overview-blur" : "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    // Only the monitor that owns the grab may close the overview
                    if (root.closeOnFocusLoss && !active && canBeActive)
                        GlobalStates.overviewOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen) {
                        if (overviewScope.appLibrary) overviewScope.appLibrary.refreshIcons();
                        delayedGrabTimer.start();
                        // The layer-shell surface can map after its declarative
                        // focus binding is evaluated. Give it an explicit Qt
                        // focus target once the window is in the scene so the
                        // local arrow/number handlers receive key events.
                        Qt.callLater(function() {
                            if (GlobalStates.overviewOpen && root.monitorIsFocused)
                                keyHandler.forceActiveFocus();
                        });
                    }
                }
            }

            // Re-evaluate grab ownership when focused monitor changes
            Connections {
                target: Hyprland
                function onFocusedMonitorChanged() {
                    if (!GlobalStates.overviewOpen)
                        return;
                    // Transfer the grab to the newly focused monitor
                    if (root.monitorIsFocused && !grab.active) {
                        grab.active = true;
                        Qt.callLater(function() {
                            if (GlobalStates.overviewOpen && root.monitorIsFocused)
                                keyHandler.forceActiveFocus();
                        });
                    } else if (!root.monitorIsFocused && grab.active) {
                        grab.active = false;
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive)
                        return;
                    grab.active = GlobalStates.overviewOpen;
                    if (grab.active)
                        keyHandler.forceActiveFocus();
                }
            }

            // Keep the layershell surface full-screen so backdrop/blur are not constrained by content size.
            implicitWidth: screen.width
            implicitHeight: screen.height

            Item {
                id: keyHandler
                anchors.fill: parent
                visible: GlobalStates.overviewOpen
                focus: GlobalStates.overviewOpen
                z: 0

                Keys.priority: Keys.BeforeItem

                Rectangle {
                    id: backdropLayer
                    anchors.fill: parent
                    visible: true
                    color: Color.launcher.scrim
                    opacity: 1
                    z: 0
                }

                MouseArea {
                    id: outsideClickCatcher
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    enabled: root.closeOnFocusLoss && GlobalStates.overviewOpen
                    z: 0
                    onPressed: mouse => {
                        GlobalStates.overviewOpen = false;
                        mouse.accepted = true;
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        overviewScope.cancelWindowSwitch();
                        event.accepted = true;
                        return;
                    }

                    const tabPressed = event.key === Qt.Key_Tab
                        || event.key === Qt.Key_Backtab;
                    if (tabPressed && !overviewScope.windowSwitching) {
                        overviewScope.resetSwitchKeyState();
                        overviewScope.windowSwitching = true;
                        modifierFallbackTimer.restart();
                    }
                    if (overviewScope.windowSwitching)
                        overviewScope.noteSwitchKeyPressed(event);

                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        overviewScope.activateSelectedWindow();
                        event.accepted = true;
                        return;
                    }

                    if (tabPressed) {
                        const reverse = event.key === Qt.Key_Backtab
                            || (event.modifiers & Qt.ShiftModifier) !== 0;
                        overviewScope.cycleWindow(reverse ? -1 : 1);
                        event.accepted = true;
                        return;
                    }

                    // Helper: compute current group bounds
                    const workspacesPerGroup = Config.options.overview.rows * Config.options.overview.columns;
                    const compositorWorkspaceId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
                    const currentId = overviewScope.workspaceSelectionActive
                        && overviewScope.selectedWorkspaceId > 0
                        ? overviewScope.selectedWorkspaceId
                        : compositorWorkspaceId;
                    const useWorkspaceMap = Config.options.overview.useWorkspaceMap;
                    const workspaceMap = Config.options.overview.workspaceMap ?? [];
                    const focusedMonitorId = Hyprland.focusedMonitor?.id ?? root.monitor?.id ?? 0;
                    const workspaceOffset = useWorkspaceMap ? Number(workspaceMap[focusedMonitorId] ?? 0) : 0;
                    const currentGroup = Math.floor((currentId - workspaceOffset - 1) / workspacesPerGroup);
                    const minWorkspaceId = currentGroup * workspacesPerGroup + 1 + workspaceOffset;
                    const maxWorkspaceId = minWorkspaceId + workspacesPerGroup - 1;

                    const rows = Config.options.overview.rows;
                    const columns = Config.options.overview.columns;
                    const reverseColumns = Config.options.overview.orderRightLeft;
                    const reverseRows = Config.options.overview.orderBottomUp;

                    const clampedIndex = Math.max(0, Math.min(workspacesPerGroup - 1, currentId - minWorkspaceId));
                    const currentNormalRow = Math.floor(clampedIndex / columns);
                    const currentNormalColumn = clampedIndex % columns;

                    function toVisualRow(normalRow) {
                        return reverseRows ? (rows - normalRow - 1) : normalRow;
                    }

                    function toVisualColumn(normalColumn) {
                        return reverseColumns ? (columns - normalColumn - 1) : normalColumn;
                    }

                    function toNormalRow(visualRow) {
                        return reverseRows ? (rows - visualRow - 1) : visualRow;
                    }

                    function toNormalColumn(visualColumn) {
                        return reverseColumns ? (columns - visualColumn - 1) : visualColumn;
                    }

                    let targetVisualRow = toVisualRow(currentNormalRow);
                    let targetVisualColumn = toVisualColumn(currentNormalColumn);

                    let targetId = null;

                    // Arrow keys and vim-style hjkl
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        targetVisualColumn = (targetVisualColumn - 1 + columns) % columns;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        targetVisualColumn = (targetVisualColumn + 1) % columns;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                        targetVisualRow = (targetVisualRow - 1 + rows) % rows;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        targetVisualRow = (targetVisualRow + 1) % rows;
                    }

                    // Number keys: jump to workspace within the current group
                    // 1-9 map to positions 1-9, 0 maps to position 10
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        const position = event.key - Qt.Key_0; // 1-9
                        if (position <= workspacesPerGroup) {
                            targetId = minWorkspaceId + position - 1;
                        }
                    } else if (event.key === Qt.Key_0) {
                        // 0 = 10th workspace in the group (if group has 10+ workspaces)
                        if (workspacesPerGroup >= 10) {
                            targetId = minWorkspaceId + 9; // 10th position = offset 9
                        }
                    }

                    if (targetId === null && (
                        event.key === Qt.Key_Left || event.key === Qt.Key_H ||
                        event.key === Qt.Key_Right || event.key === Qt.Key_L ||
                        event.key === Qt.Key_Up || event.key === Qt.Key_K ||
                        event.key === Qt.Key_Down || event.key === Qt.Key_J
                    )) {
                        const targetNormalRow = toNormalRow(targetVisualRow);
                        const targetNormalColumn = toNormalColumn(targetVisualColumn);
                        targetId = minWorkspaceId + targetNormalRow * columns + targetNormalColumn;
                    }

                    if (targetId !== null) {
                        const clampedTarget = Math.max(minWorkspaceId, Math.min(maxWorkspaceId, targetId));
			overviewScope.selectWorkspaceWindow(clampedTarget);
			if (Hyprland.usingLua) {
				Hyprland.dispatch(`hl.dsp.focus({workspace = '${clampedTarget}'})`);
			} else {
				Hyprland.dispatch("workspace " + clampedTarget);
			}
                        event.accepted = true;
                    }
                }

                Keys.onReleased: event => {
                    if (!overviewScope.windowSwitching)
                        return;

                    overviewScope.noteSwitchKeyReleased(event);
                    // modifierFallbackTimer verifies the real physical
                    // modifier state before committing the selection.
                    event.accepted = true;
                }
            }

            ColumnLayout {
                id: columnLayout
                visible: GlobalStates.overviewOpen
                z: 1
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: Config.options.position.topMargin
                }

                Loader {
                    id: overviewLoader
                    active: Config?.options.overview.enable ?? true
                    sourceComponent: OverviewWidget {
                        panelWindow: root
                        shell: overviewScope.shell
                        selectedWindowAddress: overviewScope.selectedWindowAddress
                        visible: true
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overview"

        function toggle(): string {
            overviewScope.toggle("");
            return "ok";
        }
        function close(): string {
            overviewScope.close();
            return "ok";
        }
        function open(): string {
            overviewScope.open("");
            return "ok";
        }
        function next(): string {
            overviewScope.advanceWindowSwitch(1);
            return "ok";
        }
        function previous(): string {
            overviewScope.advanceWindowSwitch(-1);
            return "ok";
        }
        function commit(): string {
            overviewScope.activateSelectedWindow();
            return "ok";
        }
        function state(): string {
            return GlobalStates.overviewOpen ? "open" : "closed";
        }
        function ping(): string {
            return "ok";
        }
    }
}
