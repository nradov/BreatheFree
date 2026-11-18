import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Post-activity summary, shown after Save. Any button exits the app.
class SummaryView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    private function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var s = getModel().summary;
        if (s == null) {
            return;
        }

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), Graphics.FONT_XTINY, str(Rez.Strings.SummarySaved), justify);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.22).toNumber(), Graphics.FONT_SMALL, s[:name] as String, justify);

        var rows = [
            [str(Rez.Strings.SummaryTime), DrawUtil.formatDuration(s[:timeMs] as Number)],
            [str(Rez.Strings.SummaryAvgResp), DrawUtil.formatRate(s[:avgRate] as Float or Null)],
            [str(Rez.Strings.SummaryAvgHr), DrawUtil.formatNumber(s[:avgHr] as Number or Null)],
            [str(Rez.Strings.SummaryMaxHr), DrawUtil.formatNumber(s[:maxHr] as Number or Null)]
        ];
        var laps = s[:laps] as Number;
        if (laps > 1) {
            rows.add([str(Rez.Strings.SummaryLaps), laps.format("%d")]);
        }

        var top = (h * 0.32).toNumber();
        var bottom = (h * 0.86).toNumber();
        var rowH = (bottom - top) / rows.size();
        var font = dc.getFontHeight(Graphics.FONT_SMALL) <= rowH ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;

        for (var i = 0; i < rows.size(); i++) {
            var y = top + rowH * i + rowH / 2;
            var halfW = DrawUtil.widthAt(dc, y) / 2 - 14;
            var row = rows[i] as Array<String>;

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - halfW, y, font, row[0], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + halfW, y, font, row[1], Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            if (i < rows.size() - 1) {
                var lineY = top + rowH * (i + 1);
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(cx - halfW, lineY, cx + halfW, lineY);
            }
        }
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        System.exit();
    }

    function onBack() as Boolean {
        System.exit();
    }

    function onSelect() as Boolean {
        System.exit();
    }
}
