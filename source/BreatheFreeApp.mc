import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Application entry point.
class BreatheFreeApp extends Application.AppBase {
    var model as ActivityModel or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary or Null) as Void {
        var m = new ActivityModel();
        model = m;
        m.startSensors();
    }

    function onStop(state as Dictionary or Null) as Void {
        var m = model;
        if (m != null) {
            m.shutdown();
        }
    }

    function getInitialView() {
        return [new DataView(), new DataDelegate()];
    }

    //! Settings changed from the Garmin Connect / Connect IQ phone app.
    function onSettingsChanged() as Void {
        var m = model;
        if (m != null) {
            m.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}

function getModel() as ActivityModel {
    return (Application.getApp() as BreatheFreeApp).model as ActivityModel;
}
