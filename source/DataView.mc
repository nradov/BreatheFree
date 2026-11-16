import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

//! The activity screens: pre-start, data pages, and the lap banner.
//! Styled after the built-in activity profiles: black background, four
//! fields separated by thin grey lines, small upper-case labels.
class DataView extends WatchUi.View {
    // Pages: 0 main fields, 1 heart rate gauge, 2 lap / time of day.
    const PAGE_COUNT = 3;
    const PAGE_GAUGE = 1;
    const PAGE_INDICATOR_MS = 2000;

    private var _page as Number = 0;
    private var _pageIndicatorUntil as Number = 0;
    private var _s as Dictionary<Symbol, String> = {} as Dictionary<Symbol, String>;
    private var _zones as Array<Number> or Null = null;

    function initialize() {
        View.initialize();
        _pageIndicatorUntil = System.getTimer();  // already expired
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
            :noHr => str(Rez.Strings.HintNoHr),
            :totalTime => str(Rez.Strings.LabelTotalTime),
            :zone => str(Rez.Strings.LabelZone)
        };
        try {
            var zones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
            _zones = (zones != null && zones.size() >= 6) ? zones : null;
        } catch (e) {
            _zones = null;
        }
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
        } else if (DrawUtil.before(m.lapAlertUntil)) {
            drawLapAlert(dc, m);
        } else if (_page == PAGE_GAUGE) {
            drawGaugePage(dc, m);
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
    // Data pages: one wide field on top, two in the middle, one at bottom
    // ------------------------------------------------------------------

    private function drawDataPage(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var paused = m.state != STATE_RECORDING;
        var blinkOff = paused && DrawUtil.phase(1000, 2) == 1;

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

        if (DrawUtil.before(_pageIndicatorUntil)) {
            drawPageIndicator(dc);
        }
    }

    // Garmin heart rate zone colors, zones 1-5.
    private function zoneColor(zone as Number) as Graphics.ColorType {
        var colors = [
            Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_BLUE,
            Graphics.COLOR_GREEN,
            Graphics.COLOR_ORANGE,
            Graphics.COLOR_RED
        ];
        if (zone < 1) {
            zone = 1;
        } else if (zone > 5) {
            zone = 5;
        }
        return colors[zone - 1] as Graphics.ColorType;
    }

    //! Heart rate as a fractional zone like the built-in gauge shows it
    //! (e.g. 2.4 = 40% of the way through zone 2), clamped to 1.0-5.9.
    //! Null if the user's zones are unavailable.
    private function zoneValue(hr as Number) as Float or Null {
        var zones = _zones;
        if (zones == null) {
            return null;
        }
        if (hr < zones[0]) {
            return 1.0;
        }
        for (var i = 1; i < 6; i++) {
            if (hr <= zones[i]) {
                var lo = zones[i - 1];
                var span = zones[i] - lo;
                var frac = span > 0 ? (hr - lo).toFloat() / span : 0.0;
                if (frac > 0.9) {
                    frac = 0.9;
                }
                return i + frac;
            }
        }
        return 5.9;
    }

    //! Heart rate value colored by zone; white if zones are unavailable.
    private function hrZoneColor(hr as Number) as Graphics.ColorType {
        var z = zoneValue(hr);
        if (z == null || (_zones != null && hr < (_zones as Array<Number>)[0])) {
            return Graphics.COLOR_WHITE;
        }
        return zoneColor(z.toNumber());
    }

    // ------------------------------------------------------------------
    // Heart rate gauge page: zone-colored arc around the bezel with a
    // pointer, as on the built-in Breathwork and Strength profiles.
    // ------------------------------------------------------------------

    const GAUGE_START = 210;  // degrees, 0 = 3 o'clock, counter-clockwise
    const GAUGE_SWEEP = 240;

    private function norm(deg as Number) as Number {
        return ((deg % 360) + 360) % 360;
    }

    private function drawGaugePage(dc as Graphics.Dc, m as ActivityModel) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var round = DrawUtil.isRound();
        var pen = (w * 0.045).toNumber();
        if (pen < 4) {
            pen = 4;
        }
        var r = cx - pen / 2 - 1;
        var seg = GAUGE_SWEEP / 5;

        // Zone segments
        dc.setPenWidth(pen);
        for (var i = 0; i < 5; i++) {
            dc.setColor(zoneColor(i + 1), Graphics.COLOR_TRANSPARENT);
            if (round) {
                var a0 = GAUGE_START - i * seg - 1;
                var a1 = GAUGE_START - (i + 1) * seg + 1;
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, norm(a0), norm(a1));
            } else {
                var x0 = 8 + i * (w - 16) / 5 + 1;
                var x1 = 8 + (i + 1) * (w - 16) / 5 - 1;
                dc.drawLine(x0, pen, x1, pen);
            }
        }
        dc.setPenWidth(1);

        var hr = m.heartRate;
        var hrOk = m.hasHeartRate();
        var zone = hrOk ? zoneValue(hr as Number) : null;

        // Pointer
        if (zone != null) {
            var frac = (zone - 1.0) / 5.0;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var size = pen + 4;
            if (round) {
                var a = Math.toRadians(GAUGE_START - frac * GAUGE_SWEEP);
                var tipR = r - pen / 2 - 2;
                var baseR = tipR - size;
                var perp = a + Math.PI / 2;
                var bx = cx + baseR * Math.cos(a);
                var by = cy - baseR * Math.sin(a);
                var half = size * 0.6;
                dc.fillPolygon([
                    [(cx + tipR * Math.cos(a)).toNumber(), (cy - tipR * Math.sin(a)).toNumber()],
                    [(bx + half * Math.cos(perp)).toNumber(), (by - half * Math.sin(perp)).toNumber()],
                    [(bx - half * Math.cos(perp)).toNumber(), (by + half * Math.sin(perp)).toNumber()]
                ]);
            } else {
                var px = (8 + frac * (w - 16)).toNumber();
                var tipY = pen + pen / 2 + 2;
                dc.fillPolygon([[px, tipY], [px - size / 2, tipY + size], [px + size / 2, tipY + size]]);
            }
        }

        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var paused = m.state != STATE_RECORDING;
        var white = Graphics.COLOR_WHITE;
        var grey = Graphics.COLOR_LT_GRAY;

        // Timer at the top (STOPPED + flashing while stopped)
        var timerLabel = paused ? label(:stopped) : label(:timer);
        var timerValue = DrawUtil.formatDuration(m.timerMs());
        if (paused && DrawUtil.phase(1000, 2) == 1) {
            timerValue = "";
        }
        var tTop = (h * 0.24).toNumber();
        DrawUtil.drawField(dc, cx, timerLabel, (h * 0.19).toNumber(), timerValue,
            [tTop, (h * 0.38).toNumber()], DrawUtil.widthAt(dc, tTop) - 2 * pen - 12,
            paused ? Graphics.COLOR_RED : grey, white);

        // Heart rate, large, with the fractional zone underneath
        var hrText = hrOk ? DrawUtil.formatNumber(hr) : "--";
        var hrFont = DrawUtil.fitFont(dc, hrText, (w * 0.5).toNumber(), (h * 0.26).toNumber());
        dc.setColor(hrOk ? hrZoneColor(hr as Number) : white, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.53).toNumber(), hrFont, hrText, justify);
        dc.setColor(grey, Graphics.COLOR_TRANSPARENT);
        var zoneText = zone != null ? label(:zone) + " " + zone.format("%.1f") : label(:hr);
        dc.drawText(cx, (h * 0.68).toNumber(), Graphics.FONT_XTINY, zoneText, justify);

        // Respiration rate at the bottom
        var bBottom = (h * 0.86).toNumber();
        DrawUtil.drawField(dc, cx, label(:resp), (h * 0.9).toNumber(), DrawUtil.formatRate(m.respRate),
            [(h * 0.72).toNumber(), bBottom], DrawUtil.widthAt(dc, bBottom) - 2 * pen - 12, grey, white);

        if (DrawUtil.before(_pageIndicatorUntil)) {
            drawPageIndicator(dc);
        }
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
