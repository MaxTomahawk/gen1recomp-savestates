local Test = dofile("tests/testlib.lua")
local T = Test.new("relative time")
local Time = dofile("src/util/Time.lua")

T:eq(Time.relative(100, 100), "NOW", "same timestamp is now")
T:eq(Time.relative(90, 149), "NOW", "less than a minute is now")
T:eq(Time.relative(90, 150), "1m", "one minute is compact")
T:eq(Time.relative(0, 3599), "59m", "minutes floor below one hour")
T:eq(Time.relative(0, 3600), "1h", "one hour is compact")
T:eq(Time.relative(0, 86400), "1d", "one day is compact")
T:eq(Time.relative(200, 100), "NOW", "future clock skew is clamped")
T:eq(Time.relative(nil, 100), "----", "missing timestamp is unavailable")
T:eq(Time.playTime(16620), "04:37", "captured play time displays hours and minutes")
T:eq(Time.playTime(59), "00:00", "play time intentionally omits incomplete minutes")
T:eq(Time.playTime(nil), "----", "missing play time is unavailable")
T:eq(Time.absolute(0), os.date("%d-%m-%Y %H:%M", 0),
  "details fallback uses dd-mm-yyyy and 24-hour time")
T:eq(Time.date(0), os.date("%d-%m-%Y", 0),
  "history date groups use the requested deterministic fallback")
T:eq(Time.historyDate(0), os.date("%H:%M", 0),
  "history rows show only time because the group already shows the date")

T:finish()
