import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The activity screens: pre-start, the data screen, and the lap banner.
//! Styled after the built-in activity profiles: black background, fields
//! separated by thin grey lines, small upper-case labels.
class DataView extends WatchUi.View {
    private var _s as Dictionary<Symbol, String> = {} as Dictionary<Symbol, String>;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _s = {
            :timer => str(Rez.Strings.LabelTimer),
            :resp => str(Rez.Strings.LabelRespRate),
            :hr => str(Rez.Strings.LabelHr),
            :stress => str(Rez.Strings.LabelStress),
            :lapTime => str(Rez.Strings.LabelLapTime),
            :totalTime => str(Rez.Strings.LabelTotalTime),
            :stopped => str(Rez.Strings.LabelStopped),
            :lap => str(Rez.Strings.LabelLap),
            :options => str(Rez.Strings.HintOptions)
        };
    }

    private function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    private function label(key as Symbol) as String {
        var value = _s[key];
        return value == null ? "" : value;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var m = getModel();
        if (m.state == STATE_READY) {
            drawReady(dc, m);
        } else if (DrawUtil.before(m.lapAlertUntil)) {
            drawLapAlert(dc, m);
        } else {
            drawDataScreen(dc, m);
        }
    }

    // ------------------------------------------------------------------
    // Pre-start screen
    // ------------------------------------------------------------------

    //! Like the built-in profiles: the data screen is already showing, under
    //! a black banner at the top that alternates every few seconds between
    //! battery + sensor status and an "Options" hint for the UP button.
    private function drawReady(dc as Graphics.Dc, m as ActivityModel) as Void {
        drawDataScreen(dc, m);

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Banner: black band across the top with a straight lower edge.
        // Proportions are measured from the built-in Cardio start screen
        // (edge at 32% of the height).
        var edge = (h * 0.32).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, edge);
        // On a black data screen the banner edge would be invisible, so
        // underline it.
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(0, edge, w, edge);
        dc.setPenWidth(1);

        if (DrawUtil.phase(BANNER_MS, 2) == 0) {
            drawStatus(dc, m, cx, h);
        } else {
            // Up arrow + "Options", one line centered at 12% of the height
            var text = label(:options);
            var font = Graphics.FONT_MEDIUM;
            var textW = dc.getTextWidthInPixels(text, font);
            var size = (h * 0.035).toNumber();  // arrow half-width
            if (size < 3) {
                size = 3;
            }
            var y = (h * 0.12).toNumber();
            var left = cx - (textW + size * 2 + 2) / 2;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[left, y + size / 2], [left + size * 2, y + size / 2], [left + size, y - size]]);
            dc.drawText(left + size * 2 + 2, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    const BANNER_MS = 3000;

    //! Battery level, then the connected-sensor icons (heart rate). The
    //! heart flashes while heart rate is still being found.
    private function drawStatus(dc as Graphics.Dc, m as ActivityModel, cx as Number, h as Number) as Void {
        var battery = System.getSystemStats().battery;
        var pct = (battery + 0.5).toNumber();
        var text = pct.format("%d") + "%";
        var font = Graphics.FONT_TINY;
        var textW = dc.getTextWidthInPixels(text, font);

        // Battery icon and percentage on one line centered at 11% of the
        // height; the icon is about 9% of the width.
        var bw = (h * 0.086).toNumber();
        var bh = (h * 0.05).toNumber();
        if (bh < 6) {
            bh = 6;
        }
        var gap = 5;
        var y = (h * 0.115).toNumber();
        var left = cx - (bw + 3 + gap + textW) / 2;
        var top = y - bh / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(left, top, bw, bh);
        dc.fillRectangle(left + bw, top + bh / 4, 3, bh / 2);
        var fill = ((bw - 4) * battery / 100.0).toNumber();
        if (fill > 0) {
            dc.setColor(battery <= 15 ? Graphics.COLOR_RED : Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left + 2, top + 2, fill, bh - 4);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + bw + 3 + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Sensor icons on a second line centered at 21% of the height
        var found = m.hasHeartRate();
        var visible = found || DrawUtil.phase(1000, 2) == 0;
        if (visible) {
            var size = (h * 0.086).toNumber();
            DrawUtil.drawHeart(dc, cx, (h * 0.21).toNumber(), size,
                found ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY);
        }
    }

    // ------------------------------------------------------------------
    // Data screen (4 fields): Timer on top, Resp Rate in the middle,
    // HR | Stress at the bottom.
    // ------------------------------------------------------------------

    private function drawDataScreen(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var white = Graphics.COLOR_WHITE;
        var grey = Graphics.COLOR_LT_GRAY;

        // While stopped, the top label reads STOPPED and the timer flashes,
        // as on the built-in activities.
        var paused = m.state == STATE_PAUSED;
        var topLabel = paused ? label(:stopped) : label(:timer);
        var topLabelColor = paused ? Graphics.COLOR_RED : grey;
        var topValue = DrawUtil.formatDuration(m.timerMs());
        if (paused && DrawUtil.phase(1000, 2) == 1) {
            topValue = "";
        }

        var y1 = (h * 0.34).toNumber();
        var y2 = (h * 0.66).toNumber();
        var botBandBottom = (h * 0.85).toNumber();

        // Separator lines
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(0, y1, w, y1);
        dc.drawLine(0, y2, w, y2);
        dc.drawLine(cx, y2, cx, botBandBottom);
        dc.setPenWidth(1);

        // Top: timer
        var topBandTop = (h * 0.15).toNumber();
        DrawUtil.drawField(dc, cx, topLabel, (h * 0.1).toNumber(), topValue,
            [topBandTop, y1 - 2], DrawUtil.widthAt(dc, topBandTop) - 12, topLabelColor, white);

        // Middle: respiration rate
        DrawUtil.drawField(dc, cx, label(:resp), y1 + (h * 0.05).toNumber(),
            DrawUtil.formatRate(m.respRate), [y1 + (h * 0.09).toNumber(), y2 - 2],
            DrawUtil.widthAt(dc, y1) - 20, grey, white);

        // Bottom: heart rate | stress (value first, label underneath)
        var botLabelY = (h * 0.9).toNumber();
        var botHalfW = DrawUtil.widthAt(dc, botBandBottom) / 2;
        var hrText = m.hasHeartRate() ? DrawUtil.formatNumber(m.heartRate) : "--";
        DrawUtil.drawField(dc, cx - botHalfW / 2 - 2, label(:hr), botLabelY, hrText,
            [y2 + 2, botBandBottom], botHalfW - 8, grey, white);
        var stress = m.stressScore;
        DrawUtil.drawField(dc, cx + botHalfW / 2 + 2, label(:stress), botLabelY,
            DrawUtil.formatNumber(stress), [y2 + 2, botBandBottom], botHalfW - 8, grey,
            stress == null ? white : stressColor(stress));
    }

    //! Stress colored by Garmin's bands: 0-25 rest, 26-50 low,
    //! 51-75 medium, 76-100 high.
    private function stressColor(score as Number) as Graphics.ColorType {
        if (score <= 25) {
            return Graphics.COLOR_BLUE;
        } else if (score <= 50) {
            return Graphics.COLOR_YELLOW;
        } else if (score <= 75) {
            return Graphics.COLOR_ORANGE;
        }
        return Graphics.COLOR_RED;
    }

    // ------------------------------------------------------------------
    // Lap banner
    // ------------------------------------------------------------------

    //! Like the built-in lap banner: lap number, then the last lap time
    //! and the total time.
    private function drawLapAlert(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var white = Graphics.COLOR_WHITE;
        var grey = Graphics.COLOR_LT_GRAY;

        dc.setColor(white, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.15).toNumber(), Graphics.FONT_SMALL,
            label(:lap) + " " + m.lapAlertNumber.format("%d"), justify);

        var y1 = (h * 0.24).toNumber();
        var mid = (h * 0.58).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(0, y1, w, y1);
        dc.drawLine(0, mid, w, mid);
        dc.setPenWidth(1);

        DrawUtil.drawField(dc, cx, label(:lapTime), y1 + (h * 0.05).toNumber(),
            DrawUtil.formatDuration(m.lapAlertTimeMs),
            [y1 + (h * 0.09).toNumber(), mid - 2], DrawUtil.widthAt(dc, y1) - 20, grey, white);

        var bottom = (h * 0.86).toNumber();
        DrawUtil.drawField(dc, cx, label(:totalTime), (h * 0.9).toNumber(),
            DrawUtil.formatDuration(m.lapAlertTotalMs),
            [mid + 2, bottom], DrawUtil.widthAt(dc, bottom) - 20, grey, white);
    }
}
