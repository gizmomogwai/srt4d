module stdiorenderer;
import renderer;
import srt;
import std.algorithm;
import std.concurrency;
import std.datetime;
import std.stdio;

void stdioController(Tid renderer) {
  foreach (line; stdin.byLine()) {
    if (line.startsWith("q")) {
      Done done;
      prioritySend(renderer, done);
      prioritySend(ownerTid(), done);
      break;
    } else if (line.startsWith("r")) {
      Rewind rewind;
      send(renderer, rewind, dur!("msecs")(line.length * 100));
    } else if (line.startsWith("f")) {
      Rewind rewind;
      send(renderer, rewind, dur!("msecs")(-line.length * 100));
    } else if (line.startsWith(" ")) {
      TogglePause p;
      send(renderer, p);
    } else {
      writeln("unknown command");
    }
  }
}

class WritelnRenderer : Renderer {
  public void show(Subtitle sub) immutable {
    writeln(sub.fStartOffset.formattedAsSrt());
    foreach (line; sub.fLines) {
      writeln(line);
    }
  }

  public void show(Duration offset) immutable {
    writeln(offset.formattedAsSrt());
  }

  public void show(string message) immutable {
    writeln(message);
  }

  public void clear() immutable {
    writeln();
    writeln();
    writeln();
  }

  public void finished() immutable {
  }
}
