import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property string loadError: ""
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var projects: []

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color muted: Color.muted
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(42), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(60), Style.font.title + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int rowSpacing: Style.spacing.xs
  property int footerHeight: Math.max(Style.space(24), Style.font.caption + Style.spacing.xs)
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(570), panel.height - Style.gapsOut * 2)

  readonly property string helperPath: root.localPath(Qt.resolvedUrl("cursor_projects.py"))

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = String(payload.fontFamily)

    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.reloadProjects()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "vegonza.omarchy-cursor")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function reloadProjects() {
    if (loadProc.running) return
    root.loading = true
    root.loadError = ""
    loadProc.command = [root.helperPath, "list"]
    loadProc.running = true
  }

  function applyLoadResult(exitCode, stdoutText, stderrText) {
    root.loading = false
    if (exitCode !== 0) {
      root.projects = []
      root.loadError = String(stderrText || "Could not read Cursor projects").trim()
      root.rebuildDisplay()
      return
    }

    var result
    try {
      result = JSON.parse(String(stdoutText || "{}"))
    } catch (error) {
      root.projects = []
      root.loadError = "Cursor returned an unreadable project list"
      root.rebuildDisplay()
      return
    }

    root.projects = Array.isArray(result.projects) ? result.projects : []
    root.loadError = String(result.error || "")
    root.rebuildDisplay()
  }

  function matchesFilter(project, tokens) {
    var haystack = [project.name, project.detail, project.projectType]
      .join(" ").toLowerCase()
    for (var i = 0; i < tokens.length; i++)
      if (haystack.indexOf(tokens[i]) === -1) return false
    return true
  }

  function rebuildDisplay() {
    var query = root.filterText.trim().toLowerCase()
    var tokens = query ? query.split(/\s+/) : []
    displayModel.clear()

    for (var i = 0; i < root.projects.length; i++) {
      var project = root.projects[i]
      if (!root.matchesFilter(project, tokens)) continue
      displayModel.append({
        projectName: String(project.name || "Project"),
        projectDetail: String(project.detail || ""),
        projectTarget: String(project.target || ""),
        projectType: String(project.projectType || (project.remote ? "Remote" : "Local")),
        remote: project.remote === true
      })
    }

    root.selectedIndex = displayModel.count > 0
      ? Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
      : 0
    root.cursorActive = displayModel.count > 0
    root.disarmPointer()
    Qt.callLater(function() {
      if (displayModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    root.disarmPointer()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.disarmPointer()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var project = displayModel.get(index)
    var command = ["uwsm-app", "--", "cursor", "--new-window"]
    if (project.remote) command.push("--folder-uri")
    command.push(project.projectTarget)
    root.dismiss()
    Quickshell.execDetached(command)
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: loadProc
    stdout: StdioCollector {
      id: loadStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: loadStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyLoadResult(exitCode, loadStdout.text, loadStderr.text)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cursor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            root.reloadProjects()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127
                     && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Column {
            anchors.left: parent.left
            anchors.right: refreshHint.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.hairline

            Text {
              width: parent.width
              text: root.filterText || "Cursor projects"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.9
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.filterText ? "Filtering recent projects" : "Type to search"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            id: refreshHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Ctrl R"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

          ListView {
            id: resultList
            anchors.fill: parent
            visible: !root.loading && !root.loadError && displayModel.count > 0
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: row
              required property int index
              required property string projectName
              required property string projectDetail
              required property string projectTarget
              required property string projectType
              required property bool remote

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: typeLabel.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.hairline

                Text {
                  width: parent.width
                  text: row.projectName
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.projectDetail
                  color: row.hasCursor ? root.selectedText : root.muted
                  opacity: row.hasCursor ? 0.8 : 1
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Text {
                id: typeLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: row.projectType.toUpperCase()
                color: row.hasCursor ? root.selectedText : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: Style.space(0.5)
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            visible: root.loading || root.loadError || displayModel.count === 0
            text: root.loading
              ? "Loading recent projects…"
              : (root.loadError || (root.filterText ? "No matching projects" : "No recent Cursor projects"))
            color: root.loadError ? Color.urgent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }

        Item {
          width: parent.width
          height: root.footerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: displayModel.count + (displayModel.count === 1 ? " project" : " projects")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Enter open  ·  Esc close"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
