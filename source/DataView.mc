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
            :breaths => str(Rez.Strings.LabelBreaths),
            :resp => str(Rez.Strings.LabelRespRate),
            :hr => str(Rez.Strings.LabelHr),
            :stress => str(Rez.Strings.LabelStress),
            :lapTime => str(Rez.Strings.LabelLapTime),
            :totalTime => str(Rez.Strings.LabelTotalTime),
            :stopped => str(Rez.Strings.LabelStopped),
            :lap => str(Rez.Strings.LabelLap),
            :start => str(Rez.Strings.HintStart),
            :settings => str(Rez.Strings.HintSettings),
            :noHr => str(Rez.Strings.HintNoHr)
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

    private function drawReady(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var hrOk = m.hasHeartRate();

        // Sensor status ring: grey and pulsing while searching, green when
        // heart rate is found (like the GPS ring of the built-in apps).
        var pulse = DrawUtil.phase(1000, 2) == 0;
        var ringColor = hrOk ? Graphics.COLOR_GREEN : (pulse ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY);
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(6);
        if (DrawUtil.isRound()) {
            dc.drawCircle(cx, h / 2, cx - 3);
        } else {
            dc.drawRectangle(3, 3, w - 6, h - 6);
        }
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.24).toNumber(), Graphics.FONT_MEDIUM, activitySessionName(m.activityType),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var hrText = hrOk ? DrawUtil.formatNumber(m.heartRate) : "--";
        var font = DrawUtil.fitFont(dc, hrText, w / 3, (h * 0.2).toNumber());
        var textW = dc.getTextWidthInPixels(hrText, font);
        var heartSize = (h * 0.1).toNumber();
        var cy = (h * 0.48).toNumber();
        var left = cx - (heartSize + 8 + textW) / 2;
        DrawUtil.drawHeart(dc, left + heartSize / 2, cy, heartSize, hrOk ? Graphics.COLOR_RED : Graphics.COLOR_DK_GRAY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + heartSize + 8, cy, font, hrText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(hrOk ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.68).toNumber(), Graphics.FONT_TINY, hrOk ? label(:start) : label(:noHr),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.8).toNumber(), Graphics.FONT_XTINY, label(:settings),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------------
    // Data screen (5 fields): Timer on top; Breaths | Resp Rate in the
    // middle; HR | Stress at the bottom.
    // ------------------------------------------------------------------

    private function drawDataScreen(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var white = Graphics.COLOR_WHITE;
        var grey = Graphics.COLOR_LT_GRAY;

        // While stopped, the top label reads STOPPED and the timer flashes,
        // as on the built-in activities.
        var paused = m.state != STATE_RECORDING;
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
        dc.drawLine(cx, y1, cx, botBandBottom);
        dc.setPenWidth(1);

        // Top: timer
        var topBandTop = (h * 0.15).toNumber();
        DrawUtil.drawField(dc, cx, topLabel, (h * 0.1).toNumber(), topValue,
            [topBandTop, y1 - 2], DrawUtil.widthAt(dc, topBandTop) - 12, topLabelColor, white);

        // Middle: breaths | respiration rate
        var halfW = DrawUtil.widthAt(dc, y1) / 2;
        var midW = halfW - 10;
        var midTop = y1 + (h * 0.09).toNumber();
        var midLabelY = y1 + (h * 0.05).toNumber();
        DrawUtil.drawField(dc, cx - halfW / 2 - 2, label(:breaths), midLabelY,
            DrawUtil.formatNumber(m.breathCount()), [midTop, y2 - 2], midW, grey, white);
        DrawUtil.drawField(dc, cx + halfW / 2 + 2, label(:resp), midLabelY,
            DrawUtil.formatRate(m.respRate), [midTop, y2 - 2], midW, grey, white);

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
