module ncursesrenderer;
import renderer;
import srt;
import std.concurrency;
import std.datetime;
import core.thread;

import deimos.ncurses.ncurses;

void nCursesController(Tid renderer) {
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
      prioritySend(ownerTid(), done);
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
