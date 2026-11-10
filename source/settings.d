module settings;

import std.conv;
import std.file : exists, readText;
import std.format;
import std.regex;
import std.string : lineSplitter, strip;


/**
 * 実行時に決めるエンジンの設定
 */
struct EngineSettings
{
    enum DEFAULT_SOURCE = "defaults";

    long hashMb = 16;               /// 置換表のサイズ（MiB）
    int threads = 1;                /// 探索スレッド数
    string source = DEFAULT_SOURCE; /// 読んだ設定ファイルのパス、または "defaults"
}


/**
 * 設定ファイルの誤り
 */
class SettingsException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}


/**
 * 設定ファイルの行をパースする
 *
 * 形式は1行に1つの "key = value"。"#" から行末まではコメント。空行は無視する。
 */
EngineSettings parseSettings(const string[] lines, string source)
{
    EngineSettings s;
    s.source = source;
    bool[string] seen;

    foreach (i, raw; lines) {
        const lineNo = i + 1;
        string line = raw;
        foreach (j, c; line) {
            if (c == '#') {
                line = line[0 .. j];
                break;
            }
        }
        line = line.strip();
        if (line.length == 0) {
            continue;
        }

        string error(string what)
        {
            return format("%s:%d: %s: '%s'", source, lineNo, what, raw);
        }

        auto m = line.matchFirst(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$");
        if (m.empty) {
            throw new SettingsException(error("expected 'key = value'"));
        }
        const string key = m[1];
        const string value = m[2];

        if (key != "hash_mb" && key != "threads") {
            throw new SettingsException(error(format("unknown key '%s' (expected hash_mb or threads)", key)));
        }
        if (key in seen) {
            throw new SettingsException(error(format("duplicate key '%s'", key)));
        }
        seen[key] = true;

        long n;
        if (value.matchFirst(r"^[0-9]+$").empty) {
            throw new SettingsException(error(format("%s must be a positive integer", key)));
        }
        try {
            n = to!long(value);
        } catch (ConvException e) {
            throw new SettingsException(error(format("%s is out of range", key)));
        }
        if (n < 1) {
            throw new SettingsException(error(format("%s must be a positive integer", key)));
        }

        if (key == "hash_mb") {
            s.hashMb = n;
        } else {
            if (n > int.max) {
                throw new SettingsException(error("threads is out of range"));
            }
            s.threads = cast(int) n;
        }
    }
    return s;
}


/**
 * 設定ファイルを読む
 *
 * ファイルが無いとき、explicit（-c で指定された）なら例外を投げ、そうでなければ既定値を返す。
 */
EngineSettings loadSettings(string path, bool explicit)
{
    if (!exists(path)) {
        if (explicit) {
            throw new SettingsException(format("%s: settings file not found", path));
        }
        return EngineSettings();
    }
    string[] lines;
    foreach (line; readText(path).lineSplitter) {
        lines ~= line;
    }
    return parseSettings(lines, path);
}


// 本番の設定
unittest
{
    auto s = parseSettings([
        "# tenuki.conf",
        "hash_mb = 262144  # 256GiB",
        "",
        "   threads=192",
    ], "tenuki.conf");
    assert(s.hashMb == 262144);
    assert(s.threads == 192);
    assert(s.source == "tenuki.conf");
}

// 片方だけ書く → もう片方は既定値
unittest
{
    auto s = parseSettings(["threads = 4"], "x.conf");
    assert(s.threads == 4);
    assert(s.hashMb == 16);
}

// コメントと空行だけ
unittest
{
    auto s = parseSettings(["# comment", "   ", ""], "x.conf");
    assert(s.hashMb == 16 && s.threads == 1);
}

version(unittest)
{
    private string errorOf(const string[] lines)
    {
        try {
            parseSettings(lines, "x.conf");
        } catch (SettingsException e) {
            return e.msg;
        }
        return null;
    }

    private bool contains(string haystack, string needle)
    {
        import std.algorithm.searching : canFind;
        return haystack !is null && haystack.canFind(needle);
    }
}

// 誤り: 行番号と行の内容がメッセージに含まれる
unittest
{
    assert(errorOf(["# c", "thread = 192"]).contains("x.conf:2"));
    assert(errorOf(["# c", "thread = 192"]).contains("thread = 192"));
    assert(errorOf(["hash_mb = 256G"]).contains("x.conf:1"));
    assert(errorOf(["threads = 0"]).contains("threads"));
    assert(errorOf(["threads = -4"]) !is null);
    assert(errorOf(["threads = "]) !is null);
    assert(errorOf(["threads = 99999999999"]) !is null);
    assert(errorOf(["hash_mb = 99999999999999999999999"]) !is null);
    assert(errorOf(["threads = 4", "threads = 8"]).contains("x.conf:2"));
    assert(errorOf(["threads 4"]).contains("expected 'key = value'"));
}

// ファイルが無い
unittest
{
    import std.file : tempDir;
    import std.path : buildPath;
    const path = buildPath(tempDir, "tenuki-settings-unittest-does-not-exist.conf");
    assert(!exists(path));

    auto s = loadSettings(path, false);
    assert(s.hashMb == 16 && s.threads == 1);
    assert(s.source == EngineSettings.DEFAULT_SOURCE);

    bool thrown = false;
    try {
        loadSettings(path, true);
    } catch (SettingsException e) {
        thrown = true;
    }
    assert(thrown);
}

// ファイルを読む
unittest
{
    import std.file : tempDir, write, remove;
    import std.path : buildPath;
    const path = buildPath(tempDir, "tenuki-settings-unittest.conf");
    write(path, "hash_mb = 64\nthreads = 4\n");
    scope(exit) remove(path);

    auto s = loadSettings(path, true);
    assert(s.hashMb == 64 && s.threads == 4);
    assert(s.source == path);
}
