import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "azzen.anime"
  ipcTarget: "azzen.anime"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // --- Episode lookup / download -----------------------------------------
  // Bundled helper that finds a show's released episodes on SubsPlease
  // (fallback Nyaa) and returns clean JSON (see anime-fetch).
  readonly property string scriptPath: Qt.resolvedUrl("anime-fetch").toString().replace(/^file:\/\//, "")
  readonly property string downloadDir: String(root.setting("downloadDir", "~/Downloads") || "~/Downloads")

  property var activeItem: null           // the anime row the picker is for
  property string activeTitle: ""
  property bool inPicker: false
  property string pickerState: "hidden"   // hidden | loading | ready | error
  property var pickerEpisodes: []
  property string pickerNote: ""
  property string pickerSource: ""
  property bool downloading: false
  property string downloadStatus: ""

  function startLookup(item) {
    if (lookupProc.running) return
    root.activeItem = item
    root.activeTitle = (item && item.title) || ""
    root.inPicker = true
    root.pickerState = "loading"
    root.pickerEpisodes = []
    root.pickerNote = ""
    root.pickerSource = ""
    root.downloading = false
    root.downloadStatus = ""
    lookupProc.command = [
      root.scriptPath,
      item.title || "",
      item.titleEnglish || "",
      item.titleJapanese || ""
    ]
    lookupProc.running = true
  }

  function exitPicker() {
    root.inPicker = false
    root.pickerState = "hidden"
    root.downloading = false
    root.downloadStatus = ""
  }

  function startDownload(ep) {
    if (!ep || !ep.magnet) return
    root.downloading = true
    root.downloadStatus = "Starting download…"
    Quickshell.execDetached([
      root.scriptPath, "download",
      ep.magnet, root.activeTitle, ep.n, root.downloadDir
    ])
    Qt.callLater(function() {
      root.downloading = false
      root.downloadStatus = "aria2c started — saving to " + root.downloadDir
    })
  }

  Process {
    id: lookupProc
    command: []
    stdout: StdioCollector {
      id: lookupOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.pickerState = "error"
          root.pickerNote = "Lookup returned nothing"
          return
        }
        var data = {}
        try { data = JSON.parse(raw) } catch (e) { data = {} }
        root.pickerEpisodes = Array.isArray(data.episodes) ? data.episodes : []
        root.pickerSource = data.source || ""
        root.pickerNote = data.note || ""
        root.pickerState = root.pickerEpisodes.length > 0 ? "ready" : "error"
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.pickerState !== "ready") {
        root.pickerState = "error"
        root.pickerNote = "Couldn't find episodes for this show"
      }
    }
  }

  // Currently airing season data. Kept stale across failures so the popup
  // never flashes empty just because a refresh hiccupped.
  property var parsed: ({ items: [], display: [], season: "", totalAiring: 0 })
  property bool loading: false
  property bool failed: false

  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 60), 10) || 60)

  // --- Pagination ---------------------------------------------------------
  // Entries (headers + rows) shown per page; the rest are reached via the
  // prev/next controls drawn under the list.
  property int pageSize: 8
  property int page: 0
  // Derived slice of `parsed.display` for the current page + page metadata.
  property var paged: Model.pageSlice(root.parsed.display, root.page, root.pageSize)
  readonly property int pageIndex: root.paged.page
  readonly property int totalPages: root.paged.totalPages

  function gotoPage(n) {
    root.page = Math.max(0, Math.min(n, root.totalPages - 1))
  }
  function nextPage() { root.gotoPage(root.pageIndex + 1) }
  function prevPage() { root.gotoPage(root.pageIndex - 1) }

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function refresh() {
    if (fetchProc.running) return
    loading = true
    failed = false
    fetchProc.running = true
  }

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "10", Model.seasonUrl()]
    stdout: StdioCollector {
      id: fetchOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.failed = true
          root.loading = false
          root.scheduleRetry()
          return
        }
        root.parsed = Model.parseSeason(raw, root.setting("maxItems", 30))
        root.page = 0
        root.failed = false
        root.loading = false
        retryCount = 0
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.failed = true
        root.loading = false
        root.scheduleRetry()
      }
    }
  }

  property int retryCount: 0
  Timer {
    id: retryTimer
    interval: 4000
    onTriggered: root.refresh()
  }
  function scheduleRetry() {
    if (retryCount >= 3) return
    retryCount++
    retryTimer.start()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    Item {
      id: content
      width: panel.contentWidth - Style.spacing.popupPadding * 2

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onCloseRequested: root.inPicker ? root.exitPicker() : root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(6)

        PanelHero {
          width: parent.width
          iconComponent: Component {
            Text {
              text: "\uF318"
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }
          }
          title: "Currently Airing"
          meta: Model.seasonLabel(root.parsed)
          detail: root.loading ? "Loading…" : String(root.parsed.totalAiring)
        }

        PanelSeparator { foreground: root.barForeground }

        Flickable {
          id: listScroll
          visible: !root.inPicker
          width: parent.width
          height: Math.min(listColumn.implicitHeight, Style.space(480))
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: listColumn
            width: listScroll.width
            spacing: Style.space(2)

            // Error / empty states, otherwise the per-day header + rows.
            Text {
              width: parent.width
              visible: root.parsed.display.length === 0
              horizontalAlignment: Text.AlignHCenter
              text: root.failed
                ? "Couldn't reach MyAnimeList"
                : (root.loading ? "Loading…" : "Nothing airing right now")
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              topPadding: Style.space(16)
              bottomPadding: Style.space(16)
            }

            Repeater {
              model: root.paged.items

              // Inline delegate rendering both day-group headers and anime
              // rows. `modelData` is valid here (Repeater context), avoiding
              // the out-of-scope ID problem of separate Component blocks.
              Item {
                id: row
                width: listColumn.width
                height: itemData.header ? headerHeight : (titleRow.visible ? Math.max(coverRect.height, textCol.implicitHeight) : coverRect.height)

                readonly property var itemData: modelData
                readonly property real headerHeight: headerText.implicitHeight
                readonly property bool isHeader: modelData.header === true
                readonly property var partInfo: Model.partInfo(row.itemData)
                readonly property string partLabel: row.itemData ? row.partInfo.label : ""
                readonly property bool isSequel: !!row.itemData && row.partInfo.number >= 2

                visible: true

                // ---- Header row (day/schedule group label) ----
                PanelSectionHeader {
                  id: headerText
                  visible: row.isHeader
                  width: parent.width
                  text: row.isHeader ? (row.itemData.label || "") : ""
                  foreground: root.barForeground
                }

                // ---- Anime row ----
                Rectangle {
                  id: rowBg
                  visible: !row.isHeader
                  anchors.fill: parent
                  color: rowMouse.hovered ? Style.hoverFill : "transparent"
                  radius: Style.cornerRadius
                }

                Row {
                  id: rowInner
                  visible: !row.isHeader
                  anchors.fill: parent
                  spacing: Style.space(10)

                  // Cover thumbnail.
                  Rectangle {
                    id: coverRect
                    width: Style.space(46)
                    height: width * 1.42
                    clip: true
                    radius: Style.cornerRadius
                    color: "transparent"

                    Image {
                      anchors.fill: parent
                      source: row.isHeader ? "" : (row.itemData.image || "")
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      smooth: true
                      sourceSize.width: width * 2
                    }
                    Rectangle {
                      anchors.fill: parent
                      color: "transparent"
                      border.width: 1
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      radius: Style.cornerRadius
                    }
                  }

                  // Title + meta column.
                  Column {
                    id: textCol
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - coverRect.width - dlButton.implicitWidth - Style.space(18)
                    spacing: Style.space(1)

                    Row {
                      id: titleRow
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        id: timeText
                        text: (row.itemData.time || "") !== "" ? row.itemData.time + " JST" : "TBA"
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      // New / Sequel badge.
                      Rectangle {
                        id: newBadge
                        width: badgeText.implicitWidth + Style.space(8)
                        height: badgeText.implicitHeight + Style.space(2)
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: row.isSequel
                          ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.45)
                          : Color.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                          id: badgeText
                          anchors.centerIn: parent
                          text: row.partLabel
                          color: row.isSequel
                            ? Qt.darker(root.barForeground, 1.4)
                            : Color.accent
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                      Text {
                        width: parent.width - timeText.width - newBadge.width - Style.space(6) * 2
                        text: row.itemData.title || ""
                        elide: Text.ElideRight
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                    }

                    Text {
                      width: parent.width
                      text: Model.typeScoreLine(row.itemData)
                      elide: Text.ElideRight
                      color: Qt.darker(root.barForeground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      width: parent.width
                      text: Model.genreLine(row.itemData)
                      elide: Text.ElideRight
                      visible: text !== ""
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  id: rowMouse
                  property bool hovered: false
                  anchors.fill: parent
                  enabled: !row.isHeader
                  hoverEnabled: true
                  onEntered: hovered = true
                  onExited: hovered = false
                  onClicked: {
                    if (row.itemData.url) Quickshell.execDetached(["xdg-open", row.itemData.url])
                    root.close()
                  }
                }

                // Download button — opens an episode picker for this show.
                // Declared last so it sits above rowMouse and keeps its own
                // clicks separate from the row's "open MAL page" action.
                Button {
                  id: dlButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "\uF019"
                  iconSize: Style.font.body
                  foreground: root.barForeground
                  tooltipText: "Find & download episodes"
                  onClicked: root.startLookup(row.itemData)
                }
              }
            }

            // ---- Pagination controls ----
            Item {
              id: pager
              visible: root.totalPages > 1
              width: parent.width
              height: visible ? pagerRow.implicitHeight : 0

              Row {
                id: pagerRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(8)
                padding: Style.space(4)

                Button {
                  text: "\uF0D9  Prev"
                  foreground: root.pageIndex > 0 ? root.barForeground : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.35)
                  fontSize: Style.font.caption
                  onClicked: root.prevPage()
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.pageIndex + 1) + " / " + root.totalPages
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Button {
                  text: "Next  \uF0DA"
                  foreground: root.pageIndex < root.totalPages - 1 ? root.barForeground : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.35)
                  fontSize: Style.font.caption
                  onClicked: root.nextPage()
                }
              }
            }
          }
        }

        // ---- Episode download picker (shown while looking up a show) ----
        Column {
          id: pickerRoot
          width: parent.width
          visible: root.inPicker
          spacing: Style.space(6)

          Row {
            id: pickerHeader
            width: parent.width
            spacing: Style.space(6)

            Button {
              id: backBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uF060"
              iconSize: Style.font.body
              foreground: root.barForeground
              tooltipText: "Back to season list"
              onClicked: root.exitPicker()
            }

            Column {
              width: parent.width - backBtn.implicitWidth - Style.space(6)
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: root.activeTitle || ""
                elide: Text.ElideRight
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                text: root.pickerNote || root.pickerSource
                elide: Text.ElideRight
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            width: parent.width
            visible: root.pickerState === "loading"
            horizontalAlignment: Text.AlignHCenter
            text: "Searching SubsPlease / Nyaa…"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            topPadding: Style.space(16)
            bottomPadding: Style.space(16)
          }

          Text {
            width: parent.width
            visible: root.pickerState === "error"
            horizontalAlignment: Text.AlignHCenter
            text: root.pickerNote || "No episodes found"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            topPadding: Style.space(16)
            bottomPadding: Style.space(16)
          }

          Flickable {
            id: pickerScroll
            visible: root.pickerState === "ready"
            width: parent.width
            height: Math.min(episodeList.implicitHeight, Style.space(380))
            contentWidth: width
            contentHeight: episodeList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
              id: episodeList
              width: pickerScroll.width
              spacing: Style.space(2)

              Repeater {
                model: root.pickerEpisodes

                Item {
                  id: epRow
                  width: episodeList.width
                  height: Math.max(textCol2.implicitHeight, magnetIcon.implicitHeight) + Style.space(8)

                  Rectangle {
                    id: epRowBg
                    anchors.fill: parent
                    color: epMouse.hovered ? Style.hoverFill : "transparent"
                    radius: Style.cornerRadius
                  }

                  Row {
                    id: epInner
                    anchors.fill: parent
                    spacing: Style.space(8)
                    padding: Style.space(4)

                    Text {
                      id: epLabel
                      anchors.verticalCenter: parent.verticalCenter
                      text: "EP " + String(modelData.n || "?")
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Column {
                      id: textCol2
                      width: parent.width - epLabel.implicitWidth - magnetIcon.implicitWidth - Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: modelData.title || ""
                        elide: Text.ElideRight
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        width: parent.width
                        visible: (modelData.size || "") !== ""
                        text: modelData.size
                        elide: Text.ElideRight
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      id: magnetIcon
                      anchors.verticalCenter: parent.verticalCenter
                      text: "\uF0C1"
                      color: Qt.darker(root.barForeground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                  }

                  MouseArea {
                    id: epMouse
                    property bool hovered: false
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: hovered = true
                    onExited: hovered = false
                    onClicked: root.startDownload(modelData)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.downloadStatus !== ""
            horizontalAlignment: Text.AlignHCenter
            text: root.downloadStatus
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }
}
