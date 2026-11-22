import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml_gui
 *
 * Configures the online map service (server, account) and toggles the basemaps
 * and orthophotos it offers. Used by the app settings page.
 */
Item {
  id: panel

  implicitHeight: layout.implicitHeight + 2 * QfTheme.popupScreenEdgeVerticalMargin

  function applyFields() {
    QfBasemapService.serverUrl = serverField.text;
    QfBasemapService.username = accountField.text;
    QfBasemapService.password = passwordField.text;
  }

  ColumnLayout {
    id: layout
    width: parent.width
    spacing: 6

    Label {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      text: qsTr("Connect to the map service to load its basemaps and orthophotos. Credentials are stored on this device only.")
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    GridLayout {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      columns: 2
      columnSpacing: 5
      rowSpacing: 5

      Label {
        text: qsTr("Server")
        font: QfTheme.defaultFont
        color: QfTheme.mainTextColor
      }

      QfTextField {
        id: serverField
        Layout.fillWidth: true
        font: QfTheme.defaultFont
        placeholderText: "https://gis.example.com:5443"
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
        text: QfBasemapService.serverUrl
        onEditingFinished: QfBasemapService.serverUrl = text
      }

      Label {
        text: qsTr("Account")
        font: QfTheme.defaultFont
        color: QfTheme.mainTextColor
      }

      QfTextField {
        id: accountField
        Layout.fillWidth: true
        font: QfTheme.defaultFont
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        text: QfBasemapService.username
        onEditingFinished: QfBasemapService.username = text
      }

      Label {
        text: qsTr("Password")
        font: QfTheme.defaultFont
        color: QfTheme.mainTextColor
      }

      QfTextField {
        id: passwordField
        Layout.fillWidth: true
        font: QfTheme.defaultFont
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase
        text: QfBasemapService.password
        onEditingFinished: QfBasemapService.password = text
      }
    }

    RowLayout {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      spacing: 6

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Connect")
        onClicked: {
          panel.applyFields();
          QfBasemapService.login();
        }
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Reload layers")
        enabled: QfBasemapService.loggedIn && !QfBasemapService.busy
        onClicked: {
          panel.applyFields();
          QfBasemapService.refresh();
        }
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Sign out")
        visible: QfBasemapService.loggedIn
        onClicked: QfBasemapService.logout()
      }
    }

    Label {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      visible: text !== ""
      text: QfBasemapService.statusMessage
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    BusyIndicator {
      Layout.alignment: Qt.AlignHCenter
      running: QfBasemapService.busy
      visible: QfBasemapService.busy
    }

    Rectangle {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      Layout.topMargin: 6
      height: 1
      color: QfTheme.controlBorderColor
    }

    Repeater {
      model: QfBasemapService.layers

      ColumnLayout {
        Layout.leftMargin: 20
        Layout.rightMargin: 20
        Layout.fillWidth: true
        spacing: 0

        Label {
          Layout.fillWidth: true
          Layout.topMargin: index === 0 || modelData.group !== QfBasemapService.layers[index - 1].group ? 10 : 0
          visible: index === 0 || modelData.group !== QfBasemapService.layers[index - 1].group
          text: modelData.group === "base" ? qsTr("Basemaps") : qsTr("Orthophotos")
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
        }

        RowLayout {
          Layout.fillWidth: true

          Label {
            Layout.fillWidth: true
            text: modelData.name
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            wrapMode: Text.WordWrap

            MouseArea {
              anchors.fill: parent
              onClicked: layerSwitch.toggle()
            }
          }

          QfSwitch {
            id: layerSwitch
            checked: modelData.enabled
            onToggled: QfBasemapService.setLayerEnabled(modelData.id, checked)
          }
        }

        Slider {
          id: opacitySlider
          Layout.fillWidth: true
          visible: modelData.enabled
          from: 0
          to: 1
          value: modelData.opacity
          property bool ready: false
          Component.onCompleted: ready = true
          // Apply the opacity live without refreshing the catalog model: a
          // model rebuild would destroy the slider while it is being dragged.
          onMoved: QfBasemapService.setLayerOpacityLive(modelData.id, value)
          // Persist and refresh the model once the drag is over.
          onPressedChanged: {
            if (ready && !pressed) {
              QfBasemapService.setLayerOpacity(modelData.id, value);
            }
          }
        }
      }
    }

    Label {
      Layout.leftMargin: 20
      Layout.rightMargin: 20
      Layout.fillWidth: true
      Layout.topMargin: 6
      visible: QfBasemapService.googleAvailable
      text: qsTr("Google satellite imagery is proxied by the map service and is intended for internal comparison only.")
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      wrapMode: Text.WordWrap
    }
  }
}
