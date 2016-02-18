module srt;

import core.time;
import std.array;
import std.conv;
import std.conv;
import std.encoding;
import std.regex;
import std.stdio;
import std.string;

struct Subtitle {
  struct Builder {
    string fNr;
    string fTime;
    string[] fLines;

    Duration convertToDuration(string h, string m, string s, string ms) {
      return dur!("msecs")(ms.to!size_t) + dur!("seconds")(s.to!size_t) + dur!("minutes")(
        m.to!size_t) + dur!("hours")(h.to!size_t);
    }

    Subtitle* add(string s) {
      if ((s == null) && (fNr != null) && (fTime != null) && (fLines.length > 0)) {
        string time = r"([0-9][0-9]):([0-9][0-9]):([0-9][0-9])[,\.]([0-9][0-9][0-9])";
        auto r = regex(time ~ " --> " ~ time);
        auto m = match(fTime, r);
        if (!m) {
          throw new Exception("unknown timestamp formt : " ~ fTime);
        }
        Duration startOffset = convertToDuration(m.captures[1], m.captures[2],
          m.captures[3], m.captures[4]);
        Duration endOffset = convertToDuration(m.captures[5], m.captures[6],
          m.captures[7], m.captures[8]);
        return new Subtitle(fNr, startOffset, endOffset, fLines.dup);
      }

      if (fNr == null) {
        fNr = s.dup;
        return null;
      }

      if (fTime == null) {
        fTime = s.dup;
        return null;
      }

      fLines ~= s.dup;
      return null;
    }
  }

  string fNr;
  string[] fLines;
  Duration fStartOffset;
  Duration fEndOffset;
  Duration fDuration;
  this(string nr, Duration startOffset, Duration endOffset, string[] lines) {
    fNr = nr;
    fLines = lines;
    fStartOffset = startOffset;
    fEndOffset = endOffset;
    fDuration = fEndOffset - fStartOffset;
  }

  int opCmp(Subtitle other) {
    return fStartOffset.opCmp(other.fStartOffset);
  }
}

struct SrtSubtitles {
  struct Builder {
    static string getFileContent(string filePath) {
      auto content = cast(const(ubyte)[]) std.file.read(filePath);
      auto e = EncodingScheme.create("utf-8");
      string res;
      auto s = e.decode(content);
      while (content.length > 0) {
        res ~= s;
        s = e.decode(content);
      }
      return res;
    }

    static SrtSubtitles parse(string filePath) {
      Subtitle[] subtitles;
      auto currentSubtitle = Subtitle.Builder();
      auto content = getFileContent(filePath);
      foreach (line; content.splitLines()) {
        auto res = currentSubtitle.add(line.length > 0 ? line.to!(string) : null);
        if (res != null) {
          subtitles ~= *res;
          currentSubtitle = Subtitle.Builder();
        }
      }
      return SrtSubtitles(subtitles.dup);
    }
  }

  Subtitle[] fSubtitles;
  this(Subtitle[] subtitles) {
    fSubtitles = subtitles;
  }
}
