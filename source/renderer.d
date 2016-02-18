module renderer;
import srt;
import std.datetime;
import std.string : format;

struct Done {
}

struct Rewind {
}

struct TogglePause {
}

interface Renderer {
  /// show subtitle
  public void show(Subtitle sub) immutable;

  /// show current position
  public void show(Duration offset) immutable;

  /// show additional message
  public void show(string message) immutable;

  public void clear() immutable;

  public void finished() immutable;
}

string formattedAsSrt(Duration d) {
  long hours;
  long minutes;
  long seconds;
  long msecs;
  d.split!("hours", "minutes", "seconds", "msecs")(hours, minutes, seconds, msecs);
  return format("%02s:%02s:%02s.%03s", hours, minutes, seconds, msecs);
}
