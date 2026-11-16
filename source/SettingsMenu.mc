import Toybox.Lang;
import Toybox.WatchUi;

//! On-watch settings, opened by holding MENU before the activity starts.
//! The same setting is also editable from the Connect IQ phone app.
module SettingsMenu {
    function show() as Void {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.SettingsTitle) as String });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettingActivityType) as String,
            $.activityTypeName($.getModel().activityType),
            :activityType,
            null));
        WatchUi.pushView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :activityType) {
            var current = getModel().activityType;
            var menu = new WatchUi.Menu2({
                :title => WatchUi.loadResource(Rez.Strings.SettingActivityType) as String,
                :focus => current == TYPE_STRENGTH ? 1 : 0
            });
            menu.addItem(new WatchUi.MenuItem(activityTypeName(TYPE_BREATHWORK), null, TYPE_BREATHWORK, null));
            menu.addItem(new WatchUi.MenuItem(activityTypeName(TYPE_STRENGTH), null, TYPE_STRENGTH, null));
            WatchUi.pushView(menu, new ActivityTypeMenuDelegate(item), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ActivityTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _parentItem as WatchUi.MenuItem;

    function initialize(parentItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var type = item.getId() as Number;
        getModel().setActivityType(type);
        _parentItem.setSubLabel(activityTypeName(type));
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
