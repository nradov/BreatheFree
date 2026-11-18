import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Title area of the Resume / Save / Discard menu. Like the built-in
//! activity profiles, it shows one metric at a time - a small label with a
//! larger value underneath - and rotates through the metrics every few
//! seconds.
class StopMenuTitle extends WatchUi.Drawable {
    const ROTATE_MS = 3000;

    private var _labels as Array<String>;

    function initialize() {
        Drawable.initialize({});
        _labels = [
            WatchUi.loadResource(Rez.Strings.LabelTime) as String,
            WatchUi.loadResource(Rez.Strings.LabelAvgResp) as String,
            WatchUi.loadResource(Rez.Strings.LabelHeartRate) as String,
            WatchUi.loadResource(Rez.Strings.LabelCalories) as String
        ];
    }

    private function value(index as Number) as String {
        var m = getModel();
        if (index == 0) {
            return DrawUtil.formatDuration(m.timerMs());
        } else if (index == 1) {
            return DrawUtil.formatRate(m.averageRespRate());
        } else if (index == 2) {
            return m.hasHeartRate() ? DrawUtil.formatNumber(m.heartRate) : "--";
        }
        var info = Activity.getActivityInfo();
        return DrawUtil.formatNumber(info != null ? info.calories : null);
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var index = DrawUtil.phase(ROTATE_MS, _labels.size());

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, h);

        // Small label in the upper part, value below it, both white as on
        // the built-in activity profiles.
        var labelH = dc.getFontHeight(Graphics.FONT_XTINY);
        var labelY = (h * 0.45).toNumber() - labelH / 2;
        if (labelY < labelH / 2) {
            labelY = labelH / 2;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, labelY, Graphics.FONT_XTINY, _labels[index],
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var top = labelY + labelH / 2;
        var text = value(index);
        var font = DrawUtil.fitFont(dc, text, (w * 0.6).toNumber(), h - top);
        dc.drawText(cx, (top + h) / 2, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
