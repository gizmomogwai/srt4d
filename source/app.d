import std.concurrency;
import std.datetime;
import std.range;
import std.stdio;
import std.typecons;

import renderer;
import srt;
import stdiorenderer;
import ncursesrenderer;

enum State {
  NoSubtitleActive,
  WaitingForSubtitle,
  SubtitleActive,
  Paused
}

void renderLoop(string filePath, immutable(Renderer) renderer) {
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
  prioritySend(ownerTid(), done);
}

void writeUsage(string[] args) {
  writeln("Usage: ", args[0], "\n", "  h|help    -- for help\n",
    "  v|verbose -- for debug\n", "  i|io -- used io (ncurses or stdio)\n");
}

void showSubtitles(string rendererClass, void function(Tid) controller, string inputFile) {
  auto renderer = cast(immutable(Renderer)) Object.factory(rendererClass);
  auto rendererThread = spawn(&renderLoop, inputFile, renderer);
  spawn(controller, rendererThread);
  receive((Done done) { writeln("first child finished"); });
  receive((Done done) { writeln("second child finished"); });
  renderer.finished();
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

  auto args2impl = [
    "stdio" : tuple("stdiorenderer.WritelnRenderer", &stdioController),
    "ncurses" : tuple("ncursesrenderer.NCursesRenderer", &nCursesController)
  ];

  if (!(io in args2impl)) {
    writeUsage(args);
    return 1;
  }

  showSubtitles(args2impl[io][0], args2impl[io][1], args[1]);
  return 0;
}
