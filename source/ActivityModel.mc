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
const FIELD_RESP_RATE = 0;
const FIELD_TOTAL_BREATHS = 1;
const FIELD_AVG_RESP_RATE = 2;
const FIELD_LAP_BREATHS = 3;
const FIELD_LAP_RESP_RATE = 4;

// How long the lap banner stays on screen.
const LAP_ALERT_MS = 4000;
// Beat intervals older than this are considered lost.
const BEAT_TIMEOUT_MS = 10000;

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
    var breaths as Float = 0.0;       // fractional while counting from a rate estimate
    var lapBreaths as Float = 0.0;
    var lapNumber as Number = 1;
    var lapStartMs as Number = 0;     // timer time at the start of the current lap

    // Lap banner
    var lapAlertUntil as Number = 0;
    var lapAlertNumber as Number = 0;
    var lapAlertTimeMs as Number = 0;
    var lapAlertTotalMs as Number = 0;

    // Captured when the activity is saved
    var summary as Dictionary or Null = null;

    private var _detector as BreathDetector;
    private var _session as ActivityRecording.Session or Null = null;
    private var _rateField as FitContributor.Field or Null = null;
    private var _totalField as FitContributor.Field or Null = null;
    private var _avgField as FitContributor.Field or Null = null;
    private var _lapBreathsField as FitContributor.Field or Null = null;
    private var _lapRateField as FitContributor.Field or Null = null;
    private var _timer as Timer.Timer or Null = null;
    private var _lastBeatMs as Number = 0;
    private var _haveBeats as Boolean = false;
    private var _lastTickMs as Number = 0;
    private var _beatListener as Boolean = false;

    function initialize() {
        _detector = new BreathDetector();
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
        if (Sensor has :registerSensorDataListener) {
            try {
                Sensor.registerSensorDataListener(method(:onSensorData), {
                    :period => 1,
                    :heartBeatIntervals => { :enabled => true }
                });
                _beatListener = true;
            } catch (e) {
                _beatListener = false;
            }
        }
        _lastTickMs = System.getTimer();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1000, true);
        _timer = timer;
    }

    function onSensorInfo(info as Sensor.Info) as Void {
        heartRate = info.heartRate;
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var hrData = data.heartRateData;
        if (hrData == null) {
            return;
        }
        var intervals = hrData.heartBeatIntervals;
        if (intervals == null || intervals.size() == 0) {
            return;
        }
        _lastBeatMs = System.getTimer();
        _haveBeats = true;
        for (var i = 0; i < intervals.size(); i++) {
            var breath = _detector.addBeat(intervals[i]);
            // Individual breaths are only counted while the detector is
            // locked onto a regular rhythm; otherwise onTick() counts from
            // the rate estimate.
            if (breath && state == STATE_RECORDING && _detector.isLocked()) {
                addBreaths(1.0);
            }
        }
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

        var beatsLive = _haveBeats && (now - _lastBeatMs) < BEAT_TIMEOUT_MS;
        var locked = beatsLive && _detector.isLocked();
        var detectedRate = beatsLive ? _detector.getRate() : null;
        var watchRate = watchRespRate();

        // Respiration rate comes from the watch's own estimate
        // (ActivityMonitor.Info.respirationRate). The beat-interval detector
        // fills in only on devices or moments where that value is missing.
        respRate = (watchRate != null) ? watchRate : detectedRate;

        if (state == STATE_RECORDING) {
            // Breath count: individual breaths while the detector is locked
            // onto a regular rhythm (counted in onSensorData), otherwise the
            // respiration rate integrated over time.
            var rate = respRate;
            if (!locked && rate != null) {
                addBreaths(rate * dt / 60.0);
            }
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                heartRate = info.currentHeartRate;
            }
            updateFitFields();
        }
        WatchUi.requestUpdate();
    }

    private function addBreaths(count as Float) as Void {
        breaths += count;
        lapBreaths += count;
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

    function breathCount() as Number {
        return breaths.toNumber();
    }

    function lapBreathCount() as Number {
        return lapBreaths.toNumber();
    }

    //! Average breaths per minute over a span of timer time.
    private function averageRate(count as Float, ms as Number) as Float or Null {
        if (ms < 10000) {
            return null;
        }
        return count * 60000.0 / ms;
    }

    function averageRespRate() as Float or Null {
        return averageRate(breaths, timerMs());
    }

    function lapAverageRespRate() as Float or Null {
        return averageRate(lapBreaths, lapTimeMs());
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
        lapBreaths = 0.0;
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
            :breaths => breathCount(),
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
        if (_beatListener) {
            Sensor.unregisterSensorDataListener();
            _beatListener = false;
        }
        Sensor.enableSensorEvents(null);
    }

    // ------------------------------------------------------------------
    // FIT developer fields
    // ------------------------------------------------------------------

    private function createFields(session as ActivityRecording.Session) as Void {
        _rateField = session.createField("resp_rate", FIELD_RESP_RATE, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "brpm" });
        _totalField = session.createField("total_breaths", FIELD_TOTAL_BREATHS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "breaths" });
        _avgField = session.createField("avg_resp_rate", FIELD_AVG_RESP_RATE, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "brpm" });
        _lapBreathsField = session.createField("lap_breaths", FIELD_LAP_BREATHS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "breaths" });
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
        field = _totalField;
        if (field != null) {
            field.setData(breathCount());
        }
        field = _avgField;
        var avg = averageRespRate();
        if (field != null && avg != null) {
            field.setData(avg);
        }
        field = _lapBreathsField;
        if (field != null) {
            field.setData(lapBreathCount());
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
