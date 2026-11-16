import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

//! The activity screens: pre-start, data pages, and the lap banner.
//! Styled after the built-in activity profiles: black background, four
//! fields separated by thin grey lines, small upper-case labels.
class DataView extends WatchUi.View {
    const PAGE_COUNT = 2;
    const PAGE_INDICATOR_MS = 2000;

    private var _page as Number = 0;
    private var _pageIndicatorUntil as Number = 0;
    private var _s as Dictionary<Symbol, String> = {} as Dictionary<Symbol, String>;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _s = {
            :timer => str(Rez.Strings.LabelTimer),
            :breaths => str(Rez.Strings.LabelBreaths),
            :resp => str(Rez.Strings.LabelRespRate),
            :hr => str(Rez.Strings.LabelHeartRate),
            :hrShort => str(Rez.Strings.LabelHr),
            :stress => str(Rez.Strings.LabelStress),
            :lapTime => str(Rez.Strings.LabelLapTime),
            :lapBreaths => str(Rez.Strings.LabelLapBreaths),
            :avgResp => str(Rez.Strings.LabelAvgResp),
            :tod => str(Rez.Strings.LabelTimeOfDay),
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

    function changePage(step as Number) as Void {
        _page = (_page + step + PAGE_COUNT) % PAGE_COUNT;
        _pageIndicatorUntil = System.getTimer() + PAGE_INDICATOR_MS;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var m = getModel();
        if (m.state == STATE_READY) {
            drawReady(dc, m);
        } else if (System.getTimer() < m.lapAlertUntil) {
            drawLapAlert(dc, m);
        } else {
            drawDataPage(dc, m);
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
        var pulse = (System.getTimer() / 1000) % 2 == 0;
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
        dc.drawText(cx, (h * 0.24).toNumber(), Graphics.FONT_MEDIUM, activityTypeName(m.activityType),
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
    // Data pages: one wide field on top, two in the middle, one at bottom
    // ------------------------------------------------------------------

    private function drawDataPage(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var paused = m.state != STATE_RECORDING;
        var blinkOff = paused && (System.getTimer() / 1000) % 2 == 1;

        var topLabel;
        var topValue;
        var midLLabel;
        var midLValue;
        var midRLabel;
        var midRValue;
        var botLabel;
        var botValue;
        if (_page == 0) {
            topLabel = label(:timer);
            topValue = DrawUtil.formatDuration(m.timerMs());
            midLLabel = label(:breaths);
            midLValue = DrawUtil.formatNumber(m.breathCount());
            midRLabel = label(:resp);
            midRValue = DrawUtil.formatRate(m.respRate);
            botLabel = label(:hr);
            botValue = m.hasHeartRate() ? DrawUtil.formatNumber(m.heartRate) : "--";
        } else {
            topLabel = label(:lapTime);
            topValue = DrawUtil.formatDuration(m.lapTimeMs());
            midLLabel = label(:lapBreaths);
            midLValue = DrawUtil.formatNumber(m.lapBreathCount());
            midRLabel = label(:avgResp);
            midRValue = DrawUtil.formatRate(m.averageRespRate());
            botLabel = label(:tod);
            botValue = DrawUtil.formatTimeOfDay();
        }

        // While stopped, the top label reads STOPPED and the timer flashes,
        // as on the built-in activities.
        var topLabelColor = Graphics.COLOR_LT_GRAY;
        if (paused) {
            topLabel = label(:stopped);
            topLabelColor = Graphics.COLOR_RED;
            if (blinkOff) {
                topValue = "";
            }
        }

        var y1 = (h * 0.34).toNumber();
        var y2 = (h * 0.66).toNumber();

        // Separator lines
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(0, y1, w, y1);
        dc.drawLine(0, y2, w, y2);
        dc.drawLine(cx, y1, cx, y2);
        dc.setPenWidth(1);

        var white = Graphics.COLOR_WHITE;
        var grey = Graphics.COLOR_LT_GRAY;

        // Top field
        var topBandTop = (h * 0.15).toNumber();
        DrawUtil.drawField(dc, cx, topLabel, (h * 0.1).toNumber(), topValue,
            [topBandTop, y1 - 2], DrawUtil.widthAt(dc, topBandTop) - 12, topLabelColor, white);

        // Middle fields
        var halfW = DrawUtil.widthAt(dc, y1) / 2;
        var midW = halfW - 10;
        var midTop = y1 + (h * 0.09).toNumber();
        var midLabelY = y1 + (h * 0.05).toNumber();
        DrawUtil.drawField(dc, cx - halfW / 2 - 2, midLLabel, midLabelY, midLValue,
            [midTop, y2 - 2], midW, grey, white);
        DrawUtil.drawField(dc, cx + halfW / 2 + 2, midRLabel, midLabelY, midRValue,
            [midTop, y2 - 2], midW, grey, white);

        // Bottom row: value first, label underneath. On the main page it is
        // split into heart rate and stress (the built-in 5-field layout).
        var botBandBottom = (h * 0.85).toNumber();
        var botLabelY = (h * 0.9).toNumber();
        if (_page == 0) {
            var botHalfW = DrawUtil.widthAt(dc, botBandBottom) / 2;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(cx, y2, cx, botBandBottom);
            dc.setPenWidth(1);
            var hrColor = m.hasHeartRate() ? hrZoneColor(m.heartRate as Number) : white;
            DrawUtil.drawField(dc, cx - botHalfW / 2 - 2, label(:hrShort), botLabelY, botValue,
                [y2 + 2, botBandBottom], botHalfW - 8, grey, hrColor);
            var stress = m.stressScore;
            DrawUtil.drawField(dc, cx + botHalfW / 2 + 2, label(:stress), botLabelY,
                DrawUtil.formatNumber(stress), [y2 + 2, botBandBottom], botHalfW - 8, grey,
                stress == null ? white : stressColor(stress));
        } else {
            DrawUtil.drawField(dc, cx, botLabel, botLabelY, botValue,
                [y2 + 2, botBandBottom], DrawUtil.widthAt(dc, botBandBottom) - 12, grey, white);
        }

        if (System.getTimer() < _pageIndicatorUntil) {
            drawPageIndicator(dc);
        }
    }

    //! Heart rate value colored by the user's heart rate zones, like the
    //! built-in heart rate gauge. White if zones are unavailable.
    private function hrZoneColor(hr as Number) as Graphics.ColorType {
        var zones = null;
        try {
            zones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
        } catch (e) {
            zones = null;
        }
        if (zones == null || zones.size() < 6) {
            return Graphics.COLOR_WHITE;
        }
        var colors = [
            Graphics.COLOR_LT_GRAY,  // zone 1
            Graphics.COLOR_BLUE,     // zone 2
            Graphics.COLOR_GREEN,    // zone 3
            Graphics.COLOR_ORANGE,   // zone 4
            Graphics.COLOR_RED       // zone 5
        ];
        if (hr < zones[0]) {
            return Graphics.COLOR_WHITE;
        }
        for (var i = 1; i < 6; i++) {
            if (hr <= zones[i]) {
                return colors[i - 1] as Graphics.ColorType;
            }
        }
        return Graphics.COLOR_RED;
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

    private function drawPageIndicator(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var x = DrawUtil.isRound() ? 12 : 6;
        var spacing = 12;
        var startY = h / 2 - (PAGE_COUNT - 1) * spacing / 2;
        for (var i = 0; i < PAGE_COUNT; i++) {
            var y = startY + i * spacing;
            if (i == _page) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 4);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, 4);
            }
        }
    }

    // ------------------------------------------------------------------
    // Lap banner
    // ------------------------------------------------------------------

    private function drawLapAlert(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.24).toNumber(), Graphics.FONT_MEDIUM,
            label(:lap) + " " + m.lapAlertNumber.format("%d"), justify);

        var time = DrawUtil.formatDuration(m.lapAlertTimeMs);
        var font = DrawUtil.fitFont(dc, time, w - 40, (h * 0.26).toNumber());
        dc.drawText(cx, (h * 0.48).toNumber(), font, time, justify);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.72).toNumber(), Graphics.FONT_SMALL,
            m.lapAlertBreaths.format("%d") + " " + label(:breaths), justify);
    }
}
