import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "azzen.anime"

  // Total count of anime in the current season, kept on the widget so the
  // icon badge is available even while the panel is closed. -1 while unknown.
  property int airingCount: -1
  property bool loading: false
  property bool failed: false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
    fetchOnce()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }
  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Refresh interval, mirrored from the panel so stale-state on the icon is
  // bounded too.
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 60), 10) || 60)

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.fetchOnce()
  }

  // Lightweight count fetch that runs on the widget, independent of the panel
  // (the icon must refresh even if the panel was never opened).
  property bool fetchedOnce: false
  function fetchOnce() {
    if (countProc.running) return
    if (root.fetchedOnce && panelLoader.item && panelLoader.item.parsed && panelLoader.item.parsed.total) {
      root.airingCount = panelLoader.item.parsed.total
      return
    }
    loading = true
    countProc.running = true
  }

  Process {
    id: countProc
    command: ["curl", "-fsS", "--max-time", "10", Model.seasonUrl()]
    stdout: StdioCollector {
      id: countOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.loading = false
          root.failed = true
          return
        }
        root.loading = false
        root.failed = false
        root.fetchedOnce = true
        var p = Model.parseSeason(raw, 0)
        root.airingCount = p.total
        // Share the fetch with the panel so it doesn't re-download on open.
        if (panelLoader.item && !panelLoader.item.failed && panelLoader.item.parsed && panelLoader.item.parsed.display.length === 0) {
          panelLoader.item.parsed = p
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.loading = false
        root.failed = true
        root.scheduleRetry()
      }
    }
  }

  property int retryCount: 0
  Timer {
    id: retryTimer
    interval: 5000
    onTriggered: root.fetchOnce()
  }
  function scheduleRetry() {
    if (retryCount >= 3) return
    retryCount++
    retryTimer.start()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF318"
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }
  }

  // Small count badge overlaid on the icon's top-right corner.
  Rectangle {
    id: badge
    visible: root.airingCount > 0
    anchors.top: button.top
    anchors.right: button.right
    anchors.topMargin: Style.space(1)
    anchors.rightMargin: Style.space(2)
    width: badgeText.implicitWidth + Style.space(6)
    height: badgeText.implicitHeight + Style.space(2)
    radius: height / 2
    color: Color.accent

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.airingCount > 999 ? "999+" : String(root.airingCount)
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(8, Style.font.caption * 0.8)
      font.bold: true
    }
  }

  readonly property string tooltip: {
    if (root.loading) return "This season's anime — loading…"
    if (root.failed) return "This season's anime — couldn't reach MyAnimeList"
    return root.airingCount >= 0
      ? "This season: " + root.airingCount + " anime (click for list)"
      : "This season's anime (click for list)"
  }
}
