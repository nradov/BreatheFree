import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Drawing and formatting helpers shared by the views.
module DrawUtil {

    // Value fonts from largest to smallest. Number fonts only contain digits
    // and a few symbols, which is all the values use.
    const VALUE_FONTS = [
        Graphics.FONT_NUMBER_THAI_HOT,
        Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM,
        Graphics.FONT_NUMBER_MILD,
        Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL,
        Graphics.FONT_TINY
    ];

    // System.getTimer() counts milliseconds since the watch booted in a
    // 32-bit signed integer, so it turns negative after about 24.8 days of
    // uptime. These helpers stay correct when that happens.

    //! (timer / periodMs) mod n, never negative. For blinking and rotating.
    function phase(periodMs as Number, n as Number) as Number {
        var p = (System.getTimer() / periodMs) % n;
        return p < 0 ? p + n : p;
    }

    //! True until a deadline computed as System.getTimer() + duration.
    function before(deadline as Number) as Boolean {
        return deadline - System.getTimer() > 0;
    }

    function isRound() as Boolean {
        return System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_RECTANGLE;
    }

    //! Usable screen width at row y (the chord of the circle on round and
    //! semi-octagon screens).
    function widthAt(dc as Graphics.Dc, y as Number) as Number {
        var w = dc.getWidth();
        if (!isRound()) {
            return w;
        }
        var r = w / 2.0;
        var d = y - dc.getHeight() / 2.0;
        var sq = r * r - d * d;
        if (sq <= 0) {
            return 0;
        }
        return (2 * Math.sqrt(sq)).toNumber();
    }

    //! Largest value font that fits text into maxW x maxH.
    function fitFont(dc as Graphics.Dc, text as String, maxW as Number, maxH as Number) as Graphics.FontDefinition {
        for (var i = 0; i < VALUE_FONTS.size(); i++) {
            var font = VALUE_FONTS[i] as Graphics.FontDefinition;
            // Number fonts carry generous internal padding, so allow the
            // font box to overflow the band a little.
            if (dc.getTextWidthInPixels(text, font) <= maxW && dc.getFontHeight(font) <= maxH * 1.15) {
                return font;
            }
        }
        return Graphics.FONT_XTINY;
    }

    //! One data field in the style of the built-in data screens: a small
    //! label and a large value centered in a band.
    //! band is [top, bottom] of the value area. (Monkey C allows at most
    //! 9 parameters per method, so the band is passed as one array.)
    function drawField(dc as Graphics.Dc, cx as Number, label as String, labelY as Number,
            value as String, band as Array<Number>, maxW as Number,
            labelColor as Graphics.ColorType, valueColor as Graphics.ColorType) as Void {
        var top = band[0];
        var bottom = band[1];
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, labelY, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (value.length() == 0) {
            return;
        }
        var font = fitFont(dc, value, maxW, bottom - top);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (top + bottom) / 2, font, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawHeart(dc as Graphics.Dc, cx as Number, cy as Number, size as Number, color as Graphics.ColorType) as Void {
        var r = size / 4;
        if (r < 2) {
            r = 2;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - r, cy - r / 2, r);
        dc.fillCircle(cx + r, cy - r / 2, r);
        dc.fillPolygon([[cx - 2 * r, cy - r / 4], [cx + 2 * r, cy - r / 4], [cx, cy + 2 * r]]);
    }

    //! 1:05, 12:34 or 1:02:03
    function formatDuration(ms as Number) as String {
        var total = ms / 1000;
        var h = total / 3600;
        var m = (total / 60) % 60;
        var s = total % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }

    //! Breaths per minute: one decimal below 10 (slow paced breathing),
    //! whole numbers above.
    function formatRate(rate as Float or Null) as String {
        if (rate == null) {
            return "--";
        }
        if (rate < 9.95) {
            return rate.format("%.1f");
        }
        return (rate + 0.5).toNumber().format("%d");
    }

    function formatNumber(value as Number or Null) as String {
        return value == null ? "--" : value.format("%d");
    }

    function formatTimeOfDay() as String {
        var t = System.getClockTime();
        var hour = t.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.format("%d") + ":" + t.min.format("%02d");
    }
}
