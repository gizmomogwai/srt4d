import core.thread;
import deimos.ncurses.ncurses;
import srt;
import std.algorithm;
import std.concurrency;
import std.datetime;
import std.range;
import std.stdio;
import std.string : format;
import std.typecons;

struct Done {
}

struct Rewind {
}

struct TogglePause {
}

enum State {
  NoSubtitleActive,
  WaitingForSubtitle,
  SubtitleActive,
  Paused
}

interface Renderer {
  public void show(Subtitle sub) immutable;
  public void show(Duration offset) immutable;
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

class NCursesRenderer : Renderer {
  import std.string;

  this() {
    import std.c.locale;

    setlocale(LC_CTYPE, "");
    initscr();
    cbreak();
    noecho();
  }

  public void show(Subtitle sub) immutable {
    erase();
    int idx = 0;
    foreach (line; sub.fLines) {
      mvprintw(idx++, 0, toStringz(line));
    }
    refresh();
  }

  public void show(Duration offset) immutable {
    mvprintw(5, 0, toStringz(offset.formattedAsSrt()));
    refresh();
  }

  public void show(string message) immutable {
    mvprintw(5, 0, toStringz(message));
    refresh();
  }

  public void clear() immutable {
    erase();
    refresh();
  }

  public void finished() immutable {
    endwin();
  }
}

class DebugNCursesRenderer : NCursesRenderer {
  override public void show(Subtitle sub) immutable {
    import std.string : toStringz;

    int idx = 0;
    mvprintw(idx++, 0, toStringz(sub.fStartOffset.formattedAsSrt()));
    foreach (line; sub.fLines) {
      mvprintw(idx++, 0, toStringz(line));
    }
    refresh();
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

void renderLoop(Tid controller, string filePath, immutable(Renderer) renderer) {
  auto subtitles = SrtSubtitles.Builder.parse(filePath);
  auto running = true;
  auto sortedSubtitles = assumeSorted(subtitles.fSubtitles);
  auto startTime = Clock.currTime();
  auto s = State.NoSubtitleActive;
  Subtitle activeSubtitle;
  Duration wait;
  Duration offsetBeforePause;
  while (running) {
    auto currentTime = Clock.currTime();
    auto currentOffset = currentTime - startTime;
    wait = Duration.zero;
    switch (s) {
    case State.NoSubtitleActive: {
        auto help = Subtitle("", currentOffset, 0.msecs(), null);
        auto nextSubtitles = sortedSubtitles.upperBound(help);
        if (nextSubtitles.length == 0) {
          wait = 1.seconds();
          break;
        }
        activeSubtitle = nextSubtitles[0];
        s = State.WaitingForSubtitle;
        wait = activeSubtitle.fStartOffset - currentOffset;
        break;
      }
    case State.WaitingForSubtitle: {
        renderer.show(activeSubtitle);
        s = State.SubtitleActive;
        wait = activeSubtitle.fEndOffset - currentOffset;
        break;
      }
    case State.SubtitleActive: {
        renderer.clear();
        s = State.NoSubtitleActive;
        break;
      }
    case State.Paused:
      wait = 1.seconds();
      break;
    default: {
        writeln("not yet implemented for ", s);
        throw new Exception("nyi");
      }
    }
    if (wait.total!("msecs") > 0) {
      receiveTimeout(wait, (Done done) { running = false; }, (OwnerTerminated msg) {
        running = false;
      }, (Rewind rewind, Duration d) {
        startTime += d;
        s = State.NoSubtitleActive;
        auto currentTime = Clock.currTime();
        auto currentOffset = currentTime - startTime;
        renderer.show(currentOffset);
      }, (TogglePause p) {
        if (s == State.Paused) {
          renderer.show("leaving pause");
          auto currentTime = Clock.currTime();
          startTime = currentTime - offsetBeforePause;
          s = State.NoSubtitleActive;
        } else {
          renderer.show("entering pause");
          auto currentTime = Clock.currTime();
          offsetBeforePause = currentTime - startTime;
          s = State.Paused;
        }
      });
    }
  }
  Done done;
  prioritySend(controller, done);
}

void stdioController(Tid mainProgram, Tid renderer) {
  foreach (line; stdin.byLine()) {
    if (line.startsWith("q")) {
      Done done;
      prioritySend(renderer, done);
      prioritySend(mainProgram, done);
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

void nCursesController(Tid mainProgram, Tid renderer) {
  int ch = getch();
  Duration[int] ffwd;
  ffwd['q'] = dur!("msecs")(100);
  ffwd['w'] = dur!("msecs")(1_000);
  ffwd['e'] = dur!("msecs")(2_000);
  ffwd['r'] = dur!("msecs")(10_000);
  ffwd['a'] = dur!("msecs")(-100);
  ffwd['s'] = dur!("msecs")(-1_000);
  ffwd['d'] = dur!("msecs")(-2_000);
  ffwd['f'] = dur!("msecs")(-10_000);
  while (true) {
    if (ch == KEY_F(10) || ch == 'X') {
      Done done;
      prioritySend(renderer, done);
      prioritySend(mainProgram, done);
      break;
    } else if (ch in ffwd) {
      Rewind rewind;
      send(renderer, rewind, ffwd[ch]);
    } else if (ch == ' ') {
      TogglePause p;
      send(renderer, p);
    } else {
      Thread.sleep(10.msecs());
    }
    ch = getch();
  }
}

void writeUsage(string[] args) {
  writeln("Usage: ", args[0], "\n", "  h|help    -- for help\n",
    "  v|verbose -- for debug\n", "  i|io -- used io (ncurses or stdio)\n");
}

int main(string[] args) {
  import std.getopt;

  auto io = "ncurses";
  auto usage = false;
  auto verbose = false;
  getopt(args, "h|help", &usage, "v|verbose", &verbose, "i|io", &io);
  if (usage) {
    writeUsage(args);
    return 0;
  }
  auto inputFile = args[1];
  auto args2impl = [
    "stdio" : tuple("app.WritelnRenderer", &stdioController),
    "ncurses" : tuple("app.NCursesRenderer", &nCursesController)
  ];
  if (!(io in args2impl)) {
    writeUsage(args);
    return 1;
  }
  auto rendererClass = args2impl[io][0];
  auto controller = args2impl[io][1];
  auto rendererInstance = cast(immutable(Renderer)) Object.factory(rendererClass);
  auto rendererThread = spawn(&renderLoop, thisTid, inputFile, rendererInstance);
  auto controllerThread = spawn(controller, thisTid, rendererThread);
  receive((Done done) { writeln("first child finished"); });
  receive((Done done) { writeln("second child finished"); });
  rendererInstance.finished();
  return 0;
}
