import srt;
import std.stdio;
import std.concurrency;
import std.datetime;
import core.thread;
import std.range;
import std.algorithm;

struct Done {}
struct Rewind {}
enum State {NoSubtitleActive, WaitingForSubtitle, SubtitleActive};

interface Renderer {
  public void show(Subtitle sub);
  public void clear();
}
class WritelnRenderer : Renderer {
  public void show(Subtitle sub) {
    foreach (line; sub.fLines) {
      writeln(line);
    }
  }
  public void clear() {
    writeln();
    writeln();
    writeln();
  }
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
  while (running) {
    auto currentTime = Clock.currTime();
    auto currentOffset = currentTime - startTime;
    wait = dur!("msecs")(0);
    switch (s) {
    case State.NoSubtitleActive: {
      auto help = Subtitle("", currentOffset, dur!("msecs")(0), null);
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
                       writeln("Rewinding ", d, " to offset ", currentOffset);
                     });
    }
  }
  Done done;
  prioritySend(controller, done);
}

void controller(Tid mainProgram, Tid renderer) {
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
    } else {
      writeln("unknown command");
    }
  }
}


void main(string[] args) {
  auto renderer = spawn(&renderLoop, thisTid, args[1], "app.WritelnRenderer");
  auto controller = spawn(&controller, thisTid, renderer);
  receive(
    (Done done) {writeln("first child finished");}
  );
  receive(
    (Done done) {writeln("second child finished");}
  );
}
