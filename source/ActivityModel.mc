import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

enum AppState {
    STATE_READY,      // activity selected, timer not started
    STATE_RECORDING,  // timer running
    STATE_PAUSED,     // timer stopped, activity not yet saved
    STATE_SAVED       // activity saved, summary showing
}

// Values of the "activityType" setting.
const TYPE_BREATHWORK = 0;
const TYPE_STRENGTH = 1;

// FIT sport / sub-sport values. Numeric so they compile with any SDK and run
// on devices whose API level predates the named constants.
const FIT_SPORT_TRAINING = 10;
const FIT_SUB_SPORT_STRENGTH_TRAINING = 20;
const FIT_SUB_SPORT_BREATHING = 62; // same as the built-in Breathwork activity

// Developer field ids; must match resources/fit/fitcontributions.xml.
// (Ids 1 and 3 held breath counts in earlier versions; don't reuse them.)
const FIELD_RESP_RATE = 0;
const FIELD_AVG_RESP_RATE = 2;
const FIELD_LAP_RESP_RATE = 4;

// How long the lap banner stays on screen.
const LAP_ALERT_MS = 4000;
// Averages need at least this much respiration data.
const MIN_AVERAGE_S = 10.0;

function readActivityType() as Number {
    var value = null;
    try {
        value = Application.Properties.getValue("activityType");
    } catch (e) {
        value = null;
    }
    return (value != null && value == TYPE_STRENGTH) ? TYPE_STRENGTH : TYPE_BREATHWORK;
}

//! Setting label: "Breathwork" or "Strength Training".
function activityTypeName(type as Number) as String {
    return WatchUi.loadResource(type == TYPE_STRENGTH ? Rez.Strings.TypeStrength : Rez.Strings.TypeBreathwork) as String;
}

//! Activity name, matching the built-in profiles: "Breathwork" or "Strength".
function activitySessionName(type as Number) as String {
    return WatchUi.loadResource(type == TYPE_STRENGTH ? Rez.Strings.NameStrength : Rez.Strings.TypeBreathwork) as String;
}

//! Owns the recording session, sensors and all live metrics.
class ActivityModel {
    var state as AppState = STATE_READY;
    var activityType as Number = TYPE_BREATHWORK;

    // Live metrics
    var heartRate as Number or Null = null;
    var respRate as Float or Null = null;
    var stressScore as Number or Null = null;  // 0-100, watch's current stress
    var lapNumber as Number = 1;
    var lapStartMs as Number = 0;     // timer time at the start of the current lap

    // Lap banner
    var lapAlertUntil as Number = 0;
    var lapAlertNumber as Number = 0;
    var lapAlertTimeMs as Number = 0;
    var lapAlertTotalMs as Number = 0;

    // Captured when the activity is saved
    var summary as Dictionary or Null = null;

    private var _session as ActivityRecording.Session or Null = null;
    private var _rateField as FitContributor.Field or Null = null;
    private var _avgField as FitContributor.Field or Null = null;
    private var _lapRateField as FitContributor.Field or Null = null;
    private var _timer as Timer.Timer or Null = null;
    private var _lastTickMs as Number = 0;
    // Time-weighted respiration rate totals (rate x seconds, seconds) for
    // the averages, over the whole activity and the current lap.
    private var _rateSum as Float = 0.0;
    private var _rateSecs as Float = 0.0;
    private var _lapRateSum as Float = 0.0;
    private var _lapRateSecs as Float = 0.0;

    function initialize() {
        lapAlertUntil = System.getTimer();  // already expired
        activityType = readActivityType();
    }

    function reloadSettings() as Void {
        // The activity type can only change before the session is created.
        if (_session == null) {
            activityType = readActivityType();
        }
    }

    function setActivityType(type as Number) as Void {
        Application.Properties.setValue("activityType", type);
        reloadSettings();
    }

    // ------------------------------------------------------------------
    // Sensors
    // ------------------------------------------------------------------

    function startSensors() as Void {
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<Sensor.SensorType>);
        Sensor.enableSensorEvents(method(:onSensorInfo));
        _lastTickMs = System.getTimer();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1000, true);
        _timer = timer;
    }

    function onSensorInfo(info as Sensor.Info) as Void {
        heartRate = info.heartRate;
    }

    //! The watch's own respiration estimate from
    //! Toybox.ActivityMonitor.Info.respirationRate (API 3.3.0+), if present.
    private function watchRespRate() as Float or Null {
        if (ActivityMonitor.Info has :respirationRate) {
            var rate = ActivityMonitor.getInfo().respirationRate;
            if (rate != null && rate > 0) {
                return rate.toFloat();
            }
        }
        return null;
    }

    //! Current stress score from Toybox.ActivityMonitor.Info.stressScore
    //! (API 5.0.0+), 0-100. Null on older devices or when unavailable.
    private function watchStressScore() as Number or Null {
        if (ActivityMonitor.Info has :stressScore) {
            var score = ActivityMonitor.getInfo().stressScore;
            if (score != null && score >= 0 && score <= 100) {
                return score;
            }
        }
        return null;
    }

    function onTick() as Void {
        var now = System.getTimer();
        stressScore = watchStressScore();
        var dt = (now - _lastTickMs) / 1000.0;
        _lastTickMs = now;
        if (dt < 0.0 || dt > 5.0) {
            dt = 1.0;
        }

        // Respiration rate comes from the watch's own estimate
        // (ActivityMonitor.Info.respirationRate).
        respRate = watchRespRate();

        if (state == STATE_RECORDING) {
            var rate = respRate;
            if (rate != null) {
                _rateSum += rate * dt;
                _rateSecs += dt;
                _lapRateSum += rate * dt;
                _lapRateSecs += dt;
            }
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                heartRate = info.currentHeartRate;
            }
            updateFitFields();
        }
        WatchUi.requestUpdate();
    }

    function hasHeartRate() as Boolean {
        return heartRate != null && heartRate > 0;
    }

    // ------------------------------------------------------------------
    // Derived values
    // ------------------------------------------------------------------

    function timerMs() as Number {
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            return info.timerTime as Number;
        }
        return 0;
    }

    function lapTimeMs() as Number {
        return timerMs() - lapStartMs;
    }

    //! Time-weighted average respiration rate, or null with too little data.
    private function average(sum as Float, secs as Float) as Float or Null {
        return secs >= MIN_AVERAGE_S ? sum / secs : null;
    }

    function averageRespRate() as Float or Null {
        return average(_rateSum, _rateSecs);
    }

    function lapAverageRespRate() as Float or Null {
        return average(_lapRateSum, _lapRateSecs);
    }

    // ------------------------------------------------------------------
    // Session control
    // ------------------------------------------------------------------

    function start() as Void {
        var session = _session;
        if (session == null) {
            activityType = readActivityType();
            var strength = activityType == TYPE_STRENGTH;
            session = ActivityRecording.createSession({
                :name => activitySessionName(activityType),
                :sport => FIT_SPORT_TRAINING as Activity.Sport,
                :subSport => (strength ? FIT_SUB_SPORT_STRENGTH_TRAINING : FIT_SUB_SPORT_BREATHING) as Activity.SubSport
            });
            _session = session;
            createFields(session);
        }
        session.start();
        state = STATE_RECORDING;
        alert(Attention.TONE_START);
    }

    function pause() as Void {
        var session = _session;
        if (session != null && session.isRecording()) {
            updateFitFields();
            session.stop();
        }
        state = STATE_PAUSED;
        alert(Attention.TONE_STOP);
    }

    function resume() as Void {
        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }
        state = STATE_RECORDING;
        alert(Attention.TONE_START);
    }

    function lap() as Void {
        var session = _session;
        if (session == null || state != STATE_RECORDING) {
            return;
        }
        var now = timerMs();
        updateFitFields();
        session.addLap();

        lapAlertNumber = lapNumber;
        lapAlertTimeMs = now - lapStartMs;
        lapAlertTotalMs = now;
        lapAlertUntil = System.getTimer() + LAP_ALERT_MS;

        lapNumber += 1;
        lapStartMs = now;
        _lapRateSum = 0.0;
        _lapRateSecs = 0.0;
        alert(Attention.TONE_LAP);
    }

    function save() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        updateFitFields();
        var info = Activity.getActivityInfo();
        summary = {
            :name => activitySessionName(activityType),
            :timeMs => timerMs(),
            :avgRate => averageRespRate(),
            :avgHr => info != null ? info.averageHeartRate : null,
            :maxHr => info != null ? info.maxHeartRate : null,
            :laps => lapNumber
        };
        if (session.isRecording()) {
            session.stop();
        }
        session.save();
        _session = null;
        state = STATE_SAVED;
        alert(Attention.TONE_SUCCESS);
    }

    function discard() as Void {
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            session.discard();
        }
        _session = null;
        state = STATE_READY;
    }

    //! Called when the app exits. An activity in progress is saved rather
    //! than lost.
    function shutdown() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
        if (_session != null && (state == STATE_RECORDING || state == STATE_PAUSED)) {
            save();
        }
        Sensor.enableSensorEvents(null);
    }

    // ------------------------------------------------------------------
    // FIT developer fields
    // ------------------------------------------------------------------

    private function createFields(session as ActivityRecording.Session) as Void {
        _rateField = session.createField("resp_rate", FIELD_RESP_RATE, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "brpm" });
        _avgField = session.createField("avg_resp_rate", FIELD_AVG_RESP_RATE, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "brpm" });
        _lapRateField = session.createField("lap_resp_rate", FIELD_LAP_RESP_RATE, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "brpm" });
    }

    //! Keeps every developer field current, so whichever FIT message the
    //! firmware writes next (record, lap or session) carries fresh values.
    private function updateFitFields() as Void {
        var rate = respRate;
        var field = _rateField;
        if (field != null && rate != null) {
            field.setData(rate);
        }
        field = _avgField;
        var avg = averageRespRate();
        if (field != null && avg != null) {
            field.setData(avg);
        }
        field = _lapRateField;
        var lapAvg = lapAverageRespRate();
        if (field != null && lapAvg != null) {
            field.setData(lapAvg);
        }
    }

    // ------------------------------------------------------------------
    // Tones and vibration, honouring the watch's system settings
    // ------------------------------------------------------------------

    private function alert(tone as Attention.Tone) as Void {
        var settings = System.getDeviceSettings();
        if (Attention has :playTone && settings.tonesOn) {
            Attention.playTone(tone);
        }
        if (Attention has :vibrate && settings.vibrateOn) {
            Attention.vibrate([new Attention.VibeProfile(75, 400)] as Array<Attention.VibeProfile>);
        }
    }
}
