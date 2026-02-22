import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    property alias cfg_showWeeklyUsage: showWeeklyCheck.checked
    property alias cfg_showPercentageText: showPercentageCheck.checked
    property alias cfg_showGraphs: showGraphsCheck.checked
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_credentialsPath: credentialsField.text

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.CheckBox {
            id: showWeeklyCheck
            Kirigami.FormData.label: i18n("Show weekly usage:")
            text: i18n("Display 7-day usage bar")
        }

        QQC2.CheckBox {
            id: showPercentageCheck
            Kirigami.FormData.label: i18n("Show percentage:")
            text: i18n("Overlay percentage text on bars")
        }

        QQC2.CheckBox {
            id: showGraphsCheck
            Kirigami.FormData.label: i18n("Show usage graphs:")
            text: i18n("Display historical usage charts")
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 15
            to: 600
            stepSize: 15
        }

        QQC2.TextField {
            id: credentialsField
            Kirigami.FormData.label: i18n("Credentials file:")
            Layout.fillWidth: true
            placeholderText: "~/.claude/.credentials.json"
        }
    }
}
