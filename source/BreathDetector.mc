import Toybox.Lang;
import Toybox.Math;

//! Detects individual breaths from beat-to-beat heart rate intervals.
//!
//! Heart rate rises while you inhale and falls while you exhale
//! (respiratory sinus arrhythmia, RSA). The detector turns each beat into an
//! instantaneous heart rate, removes the slow trend, and counts one breath
//! every time the remaining oscillation rises through an adaptive threshold.
//!
//! RSA is strong during slow, deliberate breathing (the usual breathwork
//! range of roughly 3-12 breaths per minute) and gets weaker as breathing
//! speeds up, because there are only a few heart beats per breath. The
//! detector therefore reports whether it is "locked" onto a regular breathing
//! rhythm, so the caller can fall back to the watch's own respiration
//! estimate when it is not.
class BreathDetector {
    // Beats outside this range are treated as sensor glitches.
    const MIN_IBI_MS = 270;   // 222 bpm
    const MAX_IBI_MS = 2400;  // 25 bpm
    // A beat this much shorter or longer than the running average is ignored
    // (ectopic beats, missed beats).
    const MAX_IBI_JUMP = 0.35;
    // Physiological limits on breath spacing.
    const MIN_BREATH_S = 1.5;  // 40 brpm
    const MAX_BREATH_S = 30.0; // 2 brpm
    // Number of recent breath intervals used for rate and regularity.
    const HISTORY = 4;
    // Coefficient of variation of breath intervals below which the rhythm is
    // considered regular enough to trust.
    const LOCK_CV = 0.3;

    private var _t as Float = 0.0;          // beat clock, seconds
    private var _refIbi as Float = 0.0;     // running average beat interval, s
    private var _rejects as Number = 0;
    private var _smooth as Float = 0.0;     // smoothed instantaneous HR
    private var _baseline as Float = 0.0;   // slow HR trend
    private var _amp as Float = 1.0;        // mean |oscillation|
    private var _primed as Boolean = false;
    private var _high as Boolean = false;   // currently in the "inhale" half
    private var _lastBreathT as Float = -1.0;
    private var _period as Float = 8.0;     // estimated breath period, s
    private var _intervals as Array<Float> = [] as Array<Float>;

    function initialize() {
    }

    //! Feed one beat-to-beat interval in milliseconds.
    //! @return true if this beat completed the detection of a new breath.
    function addBeat(ibiMs as Number) as Boolean {
        if (ibiMs < MIN_IBI_MS || ibiMs > MAX_IBI_MS) {
            return false;
        }
        var ibi = ibiMs / 1000.0;
        _t += ibi;

        // Artifact rejection. After several consecutive rejects, accept the
        // new level (the heart rate really did change).
        if (_refIbi > 0.0 && abs(ibi - _refIbi) / _refIbi > MAX_IBI_JUMP) {
            _rejects += 1;
            if (_rejects < 5) {
                return false;
            }
        }
        _rejects = 0;
        _refIbi = (_refIbi == 0.0) ? ibi : _refIbi + 0.1 * (ibi - _refIbi);

        var hr = 60.0 / ibi;
        if (!_primed) {
            _smooth = hr;
            _baseline = hr;
            _primed = true;
            return false;
        }

        // Filter time constants follow the current breathing period, so both
        // very slow paced breathing and faster breathing keep their shape.
        var smoothTau = clamp(_period / 10.0, 0.25, 1.5);
        var baseTau = clamp(_period, 3.0, 15.0);
        _smooth += (ibi / (smoothTau + ibi)) * (hr - _smooth);
        _baseline += (ibi / (baseTau + ibi)) * (_smooth - _baseline);
        var x = _smooth - _baseline;
        _amp += (ibi / (20.0 + ibi)) * (abs(x) - _amp);

        var threshold = _amp * 0.5;
        if (threshold < 0.4) {
            threshold = 0.4;
        }

        if (!_high && x > threshold) {
            _high = true;
            return registerBreath();
        } else if (_high && x < -threshold) {
            _high = false;
        }
        return false;
    }

    private function registerBreath() as Boolean {
        if (_lastBreathT >= 0.0) {
            var interval = _t - _lastBreathT;
            if (interval < MIN_BREATH_S) {
                return false;
            }
            if (interval <= MAX_BREATH_S) {
                _intervals.add(interval);
                if (_intervals.size() > HISTORY) {
                    _intervals = _intervals.slice(1, null);
                }
                _period += 0.3 * (interval - _period);
            }
        }
        _lastBreathT = _t;
        return true;
    }

    private function meanInterval() as Float {
        var sum = 0.0;
        for (var i = 0; i < _intervals.size(); i++) {
            sum += _intervals[i];
        }
        return sum / _intervals.size();
    }

    private function secondsSinceBreath() as Float {
        return _t - _lastBreathT;
    }

    //! Breaths per minute, or null if no recent breaths were detected.
    //! During a long exhale or breath hold the rate decays toward zero
    //! instead of freezing at the last value.
    function getRate() as Float or Null {
        if (_intervals.size() == 0) {
            return null;
        }
        var since = secondsSinceBreath();
        if (since > 60.0) {
            return null;
        }
        var mean = meanInterval();
        if (since > 1.5 * mean) {
            mean = since;
        }
        return 60.0 / mean;
    }

    //! True when the recent breaths form a regular rhythm that can be trusted
    //! for counting.
    function isLocked() as Boolean {
        if (_intervals.size() < HISTORY) {
            return false;
        }
        var mean = meanInterval();
        var since = secondsSinceBreath();
        var limit = 3.0 * mean;
        if (limit < 30.0) {
            limit = 30.0;
        }
        if (since > limit) {
            return false;
        }
        var variance = 0.0;
        for (var i = 0; i < _intervals.size(); i++) {
            var d = _intervals[i] - mean;
            variance += d * d;
        }
        variance /= _intervals.size();
        return Math.sqrt(variance) / mean < LOCK_CV;
    }

    private function abs(v as Float) as Float {
        return v < 0.0 ? -v : v;
    }

    private function clamp(v as Float, lo as Float, hi as Float) as Float {
        if (v < lo) {
            return lo;
        }
        return v > hi ? hi : v;
    }
}
