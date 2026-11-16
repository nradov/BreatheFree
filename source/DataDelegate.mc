import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Button handling for the activity screens, mirroring the built-in
//! activity profiles:
//!   START/STOP  start the timer / stop it and open the Resume-Save-Discard menu
//!   BACK/LAP    record a lap while the timer runs (exit before start)
//!   UP/DOWN     scroll data pages
//!   hold MENU   settings (before start)
class DataDelegate extends WatchUi.BehaviorDelegate {
    private var _view as DataView;

    function initialize(view as DataView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        var m = getModel();

        if (key == WatchUi.KEY_ENTER) {
            startStop(m);
            return true;
        }

        if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            if (m.state == STATE_RECORDING) {
                m.lap();
                WatchUi.requestUpdate();
                return true;
            }
            if (m.state == STATE_PAUSED) {
                showPauseMenu();
                return true;
            }
            // Before start, BACK leaves the app.
            return false;
        }
        return false;
    }

    private function startStop(m as ActivityModel) as Void {
        if (m.state == STATE_READY) {
            m.start();
        } else if (m.state == STATE_RECORDING) {
            m.pause();
            showPauseMenu();
        } else if (m.state == STATE_PAUSED) {
            m.resume();
        }
        WatchUi.requestUpdate();
    }

    private function showPauseMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.LabelStopped) as String });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuResume) as String, null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuSave) as String, null, :save, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuDiscard) as String, null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(), WatchUi.SLIDE_UP);
    }

    // A BehaviorDelegate calls the behavior method (onSelect, onBack) first
    // and only passes the raw event on to onKey / onTap / onSwipe when the
    // behavior returns false. START and BACK/LAP are handled in onKey, so
    // these two must return false to let the key events through.

    function onSelect() as Boolean {
        return false;
    }

    function onBack() as Boolean {
        return false;
    }

    //! Screen taps do nothing (the built-in apps also need a button press
    //! to start, stop or lap).
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    //! Swipe right on touch screens. Ignored during an activity so it can't
    //! be abandoned by accident; before start it leaves the app.
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_RIGHT) {
            return getModel().state != STATE_READY;
        }
        return false;
    }

    function onMenu() as Boolean {
        if (getModel().state == STATE_READY) {
            SettingsMenu.show();
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (getModel().state != STATE_READY) {
            _view.changePage(1);
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (getModel().state != STATE_READY) {
            _view.changePage(-1);
        }
        return true;
    }
}

//! Resume / Save / Discard, shown when the timer is stopped.
class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var m = getModel();
        if (id == :resume) {
            m.resume();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            m.save();
            WatchUi.switchToView(new SummaryView(), new SummaryDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :discard) {
            WatchUi.pushView(
                new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.ConfirmDiscard) as String),
                new DiscardConfirmationDelegate(),
                WatchUi.SLIDE_UP);
        }
    }

    //! Back returns to the stopped data screen; START there resumes.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class DiscardConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            getModel().discard();
            System.exit();
        }
        return true;
    }
}
