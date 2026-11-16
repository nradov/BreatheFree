# BreatheFree

An open source [Connect IQ](https://developer.garmin.com/connect-iq/) watch app for recording breathwork as a Garmin activity.

The built-in **Breathwork** activity only lets you pick from a few guided techniques. BreatheFree just records: breathe on your own, or follow any protocol you like from a book, a coach, an app on your phone or an inspiratory muscle training (IMT) device. The watch saves it as a normal activity in Garmin Connect.

Built for the **Garmin Descent Mk2**, and it runs on about 115 other Garmin watches (Connect IQ API level 3.3.0 and later, which `respirationRate` requires). Bike computers and handhelds aren't included.

## Features

- Screens styled like the built-in activity profiles: black background, four data fields, thin grey separator lines and small upper-case labels.
- **One data screen:** Timer · Breaths · Resp Rate · HR · Stress. Stress is the watch's current stress score (`ActivityMonitor.Info.stressScore`, 0–100, API 5.0.0+), colored by Garmin's rest/low/medium/high bands, and shows `--` on watches without it.
- **Laps:** BACK/LAP records a new lap. As on the built-in profiles, a lap banner shows the lap number with the last lap time and the total time, along with a tone and vibration.
- **Stop menu:** Resume / Save / Discard, like the built-in apps. Discard asks for confirmation.
- **Summary** after saving: time, breaths, avg resp rate, avg/max HR and laps.
- **Settings:** hold MENU on the start screen, or use the Connect IQ phone app.
  - *Activity Type:* **Breathwork** (default) or **Strength Training**. Use Strength Training for IMT devices such as POWERbreathe.
- **Garmin Connect data:** a respiration-rate chart, total breaths and avg respiration rate in the summary, and breaths and avg rate per lap in the Laps table. These are FIT developer fields.

### How activities are saved

| Setting | FIT sport | FIT sub-sport | Shows in Connect as |
|---|---|---|---|
| Breathwork | Training (10) | Breathing (62) | Breathwork, same as the built-in activity |
| Strength Training | Training (10) | Strength Training (20) | Strength (activity named "Strength", like the built-in profile) |

## Buttons

| Button | Before start | Timer running | Timer stopped |
|---|---|---|---|
| START/STOP | Start | Stop and open the menu | Resume |
| BACK/LAP | Exit app | **New lap** | Open the menu |
| Hold MENU | Settings | – | – |

On touch watches, screen taps and swipe-right are ignored during an activity so it can't be ended by accident. Use the buttons instead.

## How respiration rate and breaths are measured

- **Resp Rate** comes from the watch's own estimate, `Toybox.ActivityMonitor.Info.respirationRate` (API 3.3.0+). On watches that don't provide it, or while it returns no value, BreatheFree falls back to its own estimate (described next).
- **Breaths** are counted from beat-to-beat heart rate intervals (`Sensor.registerSensorDataListener` with `heartBeatIntervals`). The method relies on *respiratory sinus arrhythmia*: heart rate rises as you inhale and falls as you exhale. `BreathDetector.mc` detrends the instantaneous heart rate and counts one breath on each upswing. Its thresholds and filters adapt to your breathing pace.
  - While the detector is locked onto a regular rhythm, each detected breath is counted individually.
  - Otherwise, breaths are counted by integrating the respiration rate over time.

**Limitations**
- Detection from heart rhythm is most reliable for slow, deliberate breathing, roughly 3–12 breaths per minute. In a synthetic test, counts at 3–10 brpm were within a few percent. Above about 15 brpm there are too few heartbeats per breath, so the count relies more on the watch's rate estimate.
- Garmin developers have reported on the Connect IQ forum that `respirationRate` can read unusually low (4–5 brpm) during Breathing-type activities. If you see this, try the Strength Training type to compare.
- A wrist optical sensor works. A chest strap that broadcasts beat intervals (e.g. HRM-Pro) gives cleaner data.

## Building

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and the devices you need with the SDK Manager. Then generate a developer key.
2. Build for the Descent Mk2:
   ```sh
   monkeyc -f monkey.jungle -d descentmk2 -o bin/BreatheFree.prg -y /path/to/developer_key.der
   connectiq &                       # start the simulator
   monkeydo bin/BreatheFree.prg descentmk2
   ```
   Or open the folder in VS Code with the Monkey C extension and use **Run App**.
3. To sideload, copy `BreatheFree.prg` to `GARMIN/APPS/` on the watch over USB.
4. Store package: `monkeyc -e -f monkey.jungle -o bin/BreatheFree.iq -y developer_key.der -r`.

In the simulator, use **Simulation → FIT Data → Simulate Data** or play back a FIT file to get heart rate. Beat intervals are only available on real hardware or from FIT playback.

## Project layout

```
manifest.xml                 app id, permissions, supported watches
monkey.jungle                maps each watch to its launcher icon size
art/launcher_icon.png        master icon artwork
tools/make_launcher_icons.py regenerates icons + jungle lines (run after adding a watch)
resources-launcher-WxH/      launcher icon at each native size
resources/
  strings/strings.xml        all user-visible text (add resources-xxx/ folders to translate)
  settings/                  activityType property + phone-app setting
  fit/fitcontributions.xml   how developer fields appear in Garmin Connect
  drawables/                 default 40x40 launcher icon
source/
  BreatheFreeApp.mc          entry point
  ActivityModel.mc           session, sensors, laps, FIT fields
  BreathDetector.mc          breath detection from heartbeat intervals
  DataView.mc                pre-start, data pages, lap banner
  DataDelegate.mc            buttons, stop menu, discard confirmation
  SettingsMenu.mc            on-watch settings
  SummaryView.mc             post-save summary
  DrawUtil.mc                layout and formatting helpers
```

## Contributing

Issues and pull requests are welcome. These would be especially useful:
- Layout checks on more screen shapes, for example Instinct sub-screens and rectangular Venu Sq screens.
- Translations.
- Real-world tuning of `BreathDetector.mc`.

## License

MIT. See [LICENSE](LICENSE).

BreatheFree is not a medical device. Don't practice breath-hold exercises in or near water.
