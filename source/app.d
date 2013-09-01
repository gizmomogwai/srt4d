import srt;
import std.stdio;
import std.concurrency;
import std.datetime;
import core.thread;
import std.range;
import std.algorithm;
import deimos.ncurses.ncurses;

struct Done {}
struct Rewind {}
struct TogglePause {}
enum State {NoSubtitleActive, WaitingForSubtitle, SubtitleActive, Paused};

interface Renderer {
  public void show(Subtitle sub);
  public void show(Duration offset);
  public void clear();
  public void finished();
}
class NCursesRenderer : Renderer {
  import std.string;
  this() {
    initscr(); cbreak(); noecho();
  }
  public void show(Subtitle sub) {
    int idx = 0;
    foreach (line; sub.fLines) {
      mvprintw(idx++, 0, toStringz(line));
    }
    refresh();
  }
  public void show(Duration offset) {
    //mvprintw(5, 0, toStringz(offset.toString()));
    mvprintw(5, 0, toStringz(format("%s:%s:%s.%s", offset.hours, offset.minutes, offset.seconds, offset.fracSec.msecs)));
    //mvprintw(5, 0, toStringz(std.string.format("%s:%s:%s.%s", offset.hours, offset.minutes, offset.seconds, offset.msecs)));
    refresh();
  }
  public void clear() {
    erase();
    refresh();
  }
  public void finished() {
    endwin();
  }
}
class DebugNCursesRenderer : NCursesRenderer {
  override public void show(Subtitle sub) {
    import std.string: toStringz;
    int idx = 0;
    mvprintw(idx++, 0, toStringz(sub.fStartOffset.toString()));
    foreach (line; sub.fLines) {
      mvprintw(idx++, 0, toStringz(line));
    }
    refresh();
  }
}
class WritelnRenderer : Renderer {
  public void show(Subtitle sub) {
    writeln(sub.fStartOffset);
    foreach (line; sub.fLines) {
      writeln(line);
    }
  }
  public void show(Duration offset) {
    writeln(offset);
  }
  public void clear() {
    writeln();
    writeln();
    writeln();
  }
  public void finished() {}
}

void renderLoop(Tid controller, string filePath, string rendererClass) {
  Renderer renderer = cast(Renderer)Object.factory(rendererClass);
  auto subtitles = SrtSubtitles.Builder.parse(File(filePath));
  bool running = true;
  auto sortedSubtitles = assumeSorted(subtitles.fSubtitles);
  auto startTime = Clock.currTime();
  State s = State.NoSubtitleActive;
  Subtitle activeSubtitle;
  Duration wait;
  Duration offsetBeforePause;
  while (running) {
    auto currentTime = Clock.currTime();
    auto currentOffset = currentTime - startTime;
    wait = Duration.zero;
    switch (s) {
    case State.NoSubtitleActive: {
      auto help = Subtitle("", currentOffset, msecs(0)/*dur!("msecs")(0)*/, null);
      auto nextSubtitles = sortedSubtitles.upperBound(help);
      if (nextSubtitles.length == 0) {
        wait = dur!("seconds")(1);
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
      receiveTimeout(wait,
                     (Done done) {
                       running = false;
                     },
                     (OwnerTerminated msg) {
                       running = false;
                     },
                     (Rewind rewind, Duration d) {
                       startTime += d;
                       s = State.NoSubtitleActive;
                       auto currentTime = Clock.currTime();
                       auto currentOffset = currentTime - startTime;
                       renderer.show(currentOffset);
                     },
                     (TogglePause p) {
                       if (s == State.Paused) {
                         writeln("leaving pause");
                         auto currentTime = Clock.currTime();
                         startTime = currentTime - offsetBeforePause;
                         s = State.NoSubtitleActive;
                       } else {
                         writeln("entering pause");
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
      send(renderer, rewind, dur!("msecs")(line.length*100));
    } else if (line.startsWith("f")) {
      Rewind rewind;
      send(renderer, rewind, dur!("msecs")(-line.length*100));
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
  Duration[int] rewinds;
  rewinds['q'] = dur!("msecs")(100);
  rewinds['w'] = dur!("msecs")(1_000);
  rewinds['e'] = dur!("msecs")(2_000);
  rewinds['r'] = dur!("msecs")(10_000);
  Duration[int] forwards;
  forwards['a'] = dur!("msecs")(-100);
  forwards['s'] = dur!("msecs")(-1_000);
  forwards['d'] = dur!("msecs")(-2_000);
  forwards['f'] = dur!("msecs")(-10_000);
  while (true) {
    if (ch == KEY_F(10)) {
      Done done;
      prioritySend(renderer, done);
      prioritySend(mainProgram, done);
      break;
    } else if (ch in rewinds) {
      Rewind rewind;
      send(renderer, rewind, rewinds[ch]);
    } else if (ch in forwards) {
      Rewind rewind;
      send(renderer, rewind, forwards[ch]);
    } else if (ch == ' ') {
      TogglePause p;
      send(renderer, p);
    } else {
      Thread.sleep(dur!("msecs")(10));
    }
    ch = getch();
  }
}

int  main(string[] args) {
  import std.getopt;
  string rendererClass = "app.NCursesRenderer";
  bool usage = false;
  bool verbose = false;
  getopt(args,
         "h", &usage,
         "d", &verbose,
         "r", &rendererClass);
  if (usage) {
    writeln("Usage: ",
            args[0], "\n"
            "  h -- for help\n",
            "  d -- for debug\n",
            "  r -- renderer (app.NCursesRenderer, app.DebugNCursesRenderer, app.WritelnRenderer)\n");
    return 0;
  }
  string inputFile = args[1];
  auto renderer = spawn(&renderLoop, thisTid, inputFile, rendererClass);
  //auto controller = spawn(&nCursesController, thisTid, renderer);
  auto controller = spawn(&stdioController, thisTid, renderer);
  receive(
    (Done done) {writeln("first child finished");}
  );
  receive(
    (Done done) {writeln("second child finished");}
  );
  return 0;
}
