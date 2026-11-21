import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Controls.Material
import QtQuick.Controls.Material.impl
import QtQuick.Layouts
import org.qgis
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml_gui
 */
QfPopup {
  id: popup
  parent: mainWindow.contentItem

  signal apply

  width: mainWindow.width - QfTheme.popupScreenEdgeHorizontalMargin * 2
  height: mainWindow.height - Math.max(QfTheme.popupScreenEdgeVerticalMargin * 2, mainWindow.sceneTopMargin * 2 + 4, mainWindow.sceneBottomMargin * 2 + 4)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  focus: visible
  closePolicy: Popup.CloseOnEscape

  onAboutToHide: {
    popup.apply();
  }

  Page {
    id: page
    width: parent.width
    height: parent.height
    padding: 5
    header: QfPageHeader {
      id: pageHeader
      title: qsTr("NTRIP Settings")

      showBackButton: false
      showCancelButton: false
      showApplyButton: true

      onApply: {
        popup.close();
      }
    }

    ScrollView {
      topPadding: 0
      leftPadding: 5
      rightPadding: 5
      bottomPadding: 0
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical: QfScrollBar {}
      contentWidth: settingsLayout.childrenRect.width
      contentHeight: settingsLayout.childrenRect.height
      width: parent.width
      height: parent.height
      clip: true

      ColumnLayout {
        id: settingsLayout
        spacing: 10
        width: page.width - 20

        Label {
          text: qsTr("Service provider")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        QfComboBox {
          id: ntripProviderComboBox
          Layout.fillWidth: true
          font: QfTheme.defaultFont

          popup.font: QfTheme.defaultFont
          popup.topMargin: mainWindow.sceneTopMargin
          popup.bottomMargin: mainWindow.sceneTopMargin

          model: [qsTr("Custom"), qsTr("Qianxun FindCM"), qsTr("China Mobile CORS")]
          currentIndex: 0

          onActivated: index => {
            if (index === 1) {
              popup.applyQianxunPreset();
            } else if (index === 2) {
              popup.applyMobilePreset();
            }
          }
        }

        Label {
          visible: ntripProviderComboBox.currentIndex === 1
          text: qsTr("Qianxun: port 8001 = ITRF2008 (epoch 2016.0), 8002 = WGS84 (epoch 2005.0), 8003 = CGCS2000 (epoch 2000.0). Mount point AUTO is picked by the caster.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        Label {
          visible: ntripProviderComboBox.currentIndex === 2
          text: qsTr("China Mobile: port 8001 = CGCS2000, 8002 = WGS84. Mount point RTCM33_GRCEJ is the most precise one; use the host and credentials from your order message.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        Label {
          Layout.fillWidth: true
          text: qsTr("Paste the account message from your CORS provider and everything below is filled in automatically.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        TextArea {
          id: pasteArea
          Layout.fillWidth: true
          Layout.preferredHeight: 84
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: TextEdit.Wrap
          placeholderText: qsTr("e.g. 账号：xxx 密码：xxx IP：1.2.3.4 端口：8001（CGCS2000坐标系） 接入点：RTCM33_GRCEJ")
        }

        QfButton {
          Layout.fillWidth: true
          text: qsTr("Fill in from the pasted text")
          onClicked: popup.parseAccountText(pasteArea.text)
        }

        Label {
          id: parseFeedback
          Layout.fillWidth: true
          visible: text !== ""
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        GridLayout {
          columns: 2
          columnSpacing: 5
          rowSpacing: 10

          Label {
            text: qsTr("Host")
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Label {
            text: qsTr("Port")
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            wrapMode: Text.WordWrap
            Layout.preferredWidth: 100
          }

          QfTextField {
            id: ntripHostTextField
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
          }

          QfTextField {
            id: ntripPortTextField
            Layout.preferredWidth: 100
            font: QfTheme.defaultFont
            inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText
          }
        }

        Label {
          text: qsTr("Protocol")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        QfComboBox {
          id: ntripProtocolComboBox
          Layout.fillWidth: true
          font: QfTheme.defaultFont

          popup.font: QfTheme.defaultFont
          popup.topMargin: mainWindow.sceneTopMargin
          popup.bottomMargin: mainWindow.sceneTopMargin

          model: ListModel {
            ListElement {
              name: qsTr('NTRIP Revision 1')
              value: QfNtripSettings.NtripVersion1
            }
            ListElement {
              name: qsTr('NTRIP Revision 2')
              value: QfNtripSettings.NtripVersion2
            }
            ListElement {
              name: qsTr('NTRIP SSL/TLS')
              value: QfNtripSettings.NtripSsl
            }
          }

          textRole: "name"
          valueRole: "value"
        }

        Label {
          text: qsTr("Username")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        QfTextField {
          id: ntripUsernameTextField
          Layout.fillWidth: true
          font: QfTheme.defaultFont
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
        }

        Label {
          text: qsTr("Password")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        QfTextField {
          id: ntripPasswordTextField
          Layout.fillWidth: true
          font: QfTheme.defaultFont
          echoMode: TextInput.Password
          passwordMaskDelay: Qt.platform.os === "ios" || Qt.platform.os === "android" ? 1000 : 0
          inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
        }

        Label {
          text: qsTr("Mount point")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true

          QfComboBox {
            id: ntripMountPointComboBox
            Layout.fillWidth: true
            font: QfTheme.defaultFont

            popup.font: QfTheme.defaultFont
            popup.topMargin: mainWindow.sceneTopMargin
            popup.bottomMargin: mainWindow.sceneTopMargin

            model: []
            textRole: "mountPoint"
            valueRole: "mountPoint"

            editable: true

            delegate: MenuItem {
              id: menuItem

              required property var model
              required property int index

              padding: 16
              verticalPadding: Material.menuItemVerticalPadding
              spacing: 16

              width: ListView.view.width
              Material.foreground: ntripMountPointComboBox.currentIndex === index ? ListView.view.contentItem.Material.accent : ListView.view.contentItem.Material.foreground
              highlighted: ntripMountPointComboBox.highlightedIndex === index
              hoverEnabled: ntripMountPointComboBox.hoverEnabled

              contentItem: RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: parent.padding
                anchors.right: parent.right
                anchors.rightMargin: parent.padding
                height: menuItem.height

                Label {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                  font: ntripMountPointComboBox.font
                  color: QfTheme.mainTextColor
                  elide: Text.ElideRight
                  text: model.mountPoint
                }

                Label {
                  Layout.preferredWidth: distanceLabelMetrics.width
                  Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                  visible: text !== ''
                  font: ntripMountPointComboBox.font
                  color: QfTheme.secondaryTextColor
                  horizontalAlignment: Text.AlignRight
                  text: {
                    if (ntripMountPointComboBox.popup.visible && positionSource.positionInformation.latitudeValid) {
                      const pos = QfGeometryUtils.point(positionSource.positionInformation.longitude, positionSource.positionInformation.latitude);
                      const distance = QfGeometryUtils.distanceBetweenPoints(model.point, pos) * UnitTypes.fromUnitToUnitFactor(Qgis.DistanceUnit.Degrees, projectInfo.distanceUnits);
                      return UnitTypes.formatDistance(distance, 2, projectInfo.distanceUnits);
                    }
                    return '';
                  }
                }
              }
            }

            TextMetrics {
              id: distanceLabelMetrics
              font: ntripMountPointComboBox.font
              text: 'XXXXXXXXX'
            }
          }

          QfToolButton {
            id: refreshNtripMountPointsButton
            enabled: !ntripSourceTableFetcher.isFetching && ntripHostTextField.text !== "" && ntripPortTextField.text !== ""
            visible: !ntripSourceTableFetcher.isFetching
            iconSource: QfTheme.getThemeVectorIcon("refresh_24dp")
            iconColor: QfTheme.mainTextColor
            bgcolor: "transparent"
            Layout.preferredWidth: QfTheme.toolButtonSize
            Layout.preferredHeight: QfTheme.toolButtonSize
            padding: 0

            onClicked: {
              ntripSourceTableFetcher.fetch(QfPositioningUtils.createNtripSettings(createSettingsMap()));
            }
          }

          BusyIndicator {
            id: refreshNtripMountPointsIndicator
            Layout.margins: 6
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            running: ntripSourceTableFetcher.isFetching
            visible: ntripSourceTableFetcher.isFetching
          }
        }

        Label {
          id: ntripMountPointsDetails
          visible: text !== ""
          font: QfTheme.defaultFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          Layout.leftMargin: 10
          text: {
            const mountPoint = ntripMountPointComboBox.editText;
            const idx = ntripMountPointComboBox.indexOfValue(mountPoint);
            let details = [];
            if (idx > -1) {
              if (ntripMountPointComboBox.model[idx].identifier !== '') {
                details.push(qsTr("Identifier:") + " " + ntripMountPointComboBox.model[idx].identifier);
              }
              if (ntripMountPointComboBox.model[idx].format !== '') {
                details.push(qsTr("Data format:") + " " + ntripMountPointComboBox.model[idx].format);
              }
              if (positionSource.positionInformation.latitudeValid) {
                const pos = QfGeometryUtils.point(positionSource.positionInformation.longitude, positionSource.positionInformation.latitude);
                const distance = QfGeometryUtils.distanceBetweenPoints(ntripMountPointComboBox.model[idx].point, pos) * UnitTypes.fromUnitToUnitFactor(Qgis.DistanceUnit.Degrees, projectInfo.distanceUnits);
                details.push(qsTr("Distance:") + " " + UnitTypes.formatDistance(distance, 2, projectInfo.distanceUnits));
              }
            }
            return details.join('\n');
          }
        }

        Label {
          id: refreshNtripMountPointsFeedback
          visible: text !== ""
          font: QfTheme.defaultFont
          color: QfTheme.errorColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          Layout.leftMargin: 10
        }

        RowLayout {
          Layout.fillWidth: true

          Label {
            id: ntripForwardNmeaSentencesLabel
            Layout.fillWidth: true
            text: qsTr('Forward position to NTRIP caster')
            font: QfTheme.defaultFont
            wrapMode: Text.WordWrap

            MouseArea {
              anchors.fill: parent
              onClicked: ntripForwardNmeaSentencesSwitch.toggle()
            }
          }

          QfSwitch {
            id: ntripForwardNmeaSentencesSwitch
            Layout.preferredWidth: QfTheme.toolButtonSize
          }
        }
      }
    }
  }

  QfNtripSourceTableFetcher {
    id: ntripSourceTableFetcher

    onMountPointsChanged: {
      // Preserve edited mountpoint text after model update
      const previousMountPoint = ntripMountPointComboBox.editText;
      let mps = [...mountPoints];
      if (positionSource.positionInformation.latitudeValid) {
        const pos = QfGeometryUtils.point(positionSource.positionInformation.longitude, positionSource.positionInformation.latitude);
        mps.sort((a, b) => {
          return QfGeometryUtils.distanceBetweenPoints(a.point, pos) > QfGeometryUtils.distanceBetweenPoints(b.point, pos) ? 1 : -1;
        });
      } else {
        mps.sort((a, b) => {
          return a.mountPoint > b.mountPoint ? 1 : -1;
        });
      }
      ntripMountPointComboBox.model = mps;
      if (previousMountPoint !== "") {
        const idx = ntripMountPointComboBox.indexOfValue(previousMountPoint);
        if (idx > -1) {
          ntripMountPointComboBox.currentIndex = idx;
        } else {
          ntripMountPointComboBox.currentIndex = -1;
          ntripMountPointComboBox.editText = previousMountPoint;
        }
      } else {
        ntripMountPointComboBox.currentIndex = 0;
      }
    }

    onFetchError: function (message) {
      refreshNtripMountPointsFeedback.text = message;
    }
  }

  function updateFromNtripSettings(ntripSettings) {
    ntripHostTextField.text = ntripSettings.host;
    ntripPortTextField.text = ntripSettings.port;
    ntripProtocolComboBox.currentValue = ntripSettings.protocol;
    ntripUsernameTextField.text = ntripSettings.username;
    ntripPasswordTextField.text = ntripSettings.password;
    ntripMountPointComboBox.editText = ntripSettings.mountPoint;
    ntripForwardNmeaSentencesSwitch.checked = ntripSettings.forwardNmeaSentences;
    ntripProviderComboBox.currentIndex = ntripSettings.host === "rtk.ntrip.qxwz.com" ? 1 : 0;
  }

  /**
   * Fills in the public endpoint of the Qianxun (FindCM) NTRIP service.
   * Credentials are deliberately left untouched, and the protocol stays as
   * selected by the user since the caster accepts both NTRIP revisions.
   */
  function applyQianxunPreset() {
    ntripHostTextField.text = "rtk.ntrip.qxwz.com";
    ntripPortTextField.text = "8003";
    ntripMountPointComboBox.editText = "AUTO";
    ntripForwardNmeaSentencesSwitch.checked = true;
    ntripProviderComboBox.currentIndex = 1;
  }

  function applyMobilePreset() {
    ntripHostTextField.text = "120.253.239.161";
    ntripPortTextField.text = "8001";
    ntripMountPointComboBox.editText = "RTCM33_GRCEJ";
    ntripForwardNmeaSentencesSwitch.checked = true;
    ntripProviderComboBox.currentIndex = 2;
  }

  /**
   * Parses the order / SMS text that Chinese CORS providers send and fills the
   * form. Handles both full width and ASCII colons, "或"-separated hosts and
   * ports annotated with their coordinate frame (prefers CGCS2000).
   */
  function parseAccountText(text) {
    const normalized = (text || "").replace(/：/g, ":").replace(/\r/g, "");

    const pick = (pattern) => {
      const match = normalized.match(pattern);
      return match ? match[1].trim() : "";
    };

    const account = pick(/账号\s*[:=]\s*([^\s,;，；]+)/) || pick(/用户名\s*[:=]\s*([^\s,;，；]+)/);
    const password = pick(/密码\s*[:=]\s*([^\s,;，；]+)/);
    const host = pick(/(?:IP|域名|地址|主机|服务器)\s*[:=]\s*([^\s,;，；或]+)/i);
    const mountPoint = pick(/(?:接入点|挂载点|mount\s*point|mountpoint|源节点)\s*[:=]\s*([A-Za-z0-9_\-]+)/i);

    // Port: several ports can be listed, each annotated with its coordinate
    // frame ("8001（CGCS2000坐标系）；8002（WGS84坐标系）"). Prefer CGCS2000.
    let port = "";
    let portFallback = "";
    const portSegments = normalized.split(/端口|port/i);
    for (let i = 1; i < portSegments.length; i++) {
      const segment = portSegments[i];
      const number = segment.match(/^[\s:=]*?(\d{4,5})/);
      if (!number) {
        continue;
      }
      const context = segment.slice(0, 60);
      if (/CGCS2000/i.test(context)) {
        port = number[1];
        break;
      }
      if (!portFallback && /WGS84|ITRF|CGCS/i.test(context)) {
        portFallback = number[1];
      }
    }
    if (!port) {
      port = portFallback || pick(/端口\s*[:=]\s*(\d{4,5})/);
    }

    let providerIndex = 0;
    if (/千寻|FindCM|知寸/i.test(normalized)) {
      providerIndex = 1;
    } else if (/移动|CMCC/i.test(normalized)) {
      providerIndex = 2;
    }

    if (providerIndex === 1) {
      popup.applyQianxunPreset();
    } else if (providerIndex === 2) {
      popup.applyMobilePreset();
    }

    if (account) {
      ntripUsernameTextField.text = account;
    }
    if (password) {
      ntripPasswordTextField.text = password;
    }
    if (host) {
      ntripHostTextField.text = host;
    }
    if (port) {
      ntripPortTextField.text = port;
    }
    if (mountPoint) {
      ntripMountPointComboBox.editText = mountPoint;
    }
    if (account || password || host || port || mountPoint) {
      ntripForwardNmeaSentencesSwitch.checked = true;
    }

    let details = [];
    if (account) {
      details.push(qsTr("account %1").arg(account));
    }
    if (mountPoint) {
      details.push(qsTr("mount point %1").arg(mountPoint));
    }
    if (port) {
      details.push(qsTr("port %1").arg(port));
    }
    parseFeedback.text = details.length > 0
      ? qsTr("Filled in: %1").arg(details.join(", "))
      : qsTr("No recognizable field found in the pasted text.");
  }

  function createSettingsMap() {
    return {
      "host": ntripHostTextField.text,
      "port": ntripPortTextField.text,
      "protocol": ntripProtocolComboBox.currentValue,
      "username": ntripUsernameTextField.text,
      "password": ntripPasswordTextField.text,
      "mountPoint": ntripMountPointComboBox.editText,
      "forwardNmeaSentences": ntripForwardNmeaSentencesSwitch.checked
    };
  }
}
