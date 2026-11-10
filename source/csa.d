module csa;

import config;
import std.conv;
import std.format;
import std.regex;
import types;


/**
 * Game_Summary の内容
 */
struct GameSummary
{
    color_t us;                     /// 自分の手番
    long totalSeconds;              /// 持ち時間（秒）
    long incrementSeconds;          /// 1手ごとの加算（秒）
    string[] initialMoves;          /// BEGIN Position 内の指し手（"+5958OU,T422" 形式）
    string[string] fields;          /// BEGIN Time / BEGIN Position 以外の key:value
    string[] warnings;              /// 既定値を使った、未対応の値だった、などの警告
}


/**
 * Game_Summary の行（BEGIN Game_Summary 〜 END Game_Summary）をパースする
 */
GameSummary parseGameSummary(const string[] lines)
{
    GameSummary s;
    string[string] time;
    string section = ""; // "" はトップレベル

    foreach (line; lines) {
        if (line == "BEGIN Game_Summary" || line == "END Game_Summary") {
            continue;
        }
        auto begin = line.matchFirst(r"^BEGIN (.+)$");
        if (!begin.empty) {
            section = begin[1];
            continue;
        }
        if (line.matchFirst(r"^END .+$")) {
            section = "";
            continue;
        }

        auto kv = line.matchFirst(r"^([^:]+):(.*)$");
        if (section == "Time") {
            if (!kv.empty) time[kv[1]] = kv[2];
        } else if (section == "Position") {
            if (isMoveLine(line)) s.initialMoves ~= line;
        } else if (section == "") {
            if (!kv.empty) s.fields[kv[1]] = kv[2];
        }
        // それ以外のブロック（BEGIN Time+ など）は読まない
    }

    auto yourTurn = "Your_Turn" in s.fields;
    if (yourTurn is null || (*yourTurn != "+" && *yourTurn != "-")) {
        throw new Exception("Game_Summary: Your_Turn is missing or invalid");
    }
    s.us = (*yourTurn == "+" ? Color.BLACK : Color.WHITE);

    s.totalSeconds = readSeconds(time, "Total_Time", Config.TOTAL_SECONDS, s.warnings);
    s.incrementSeconds = readSeconds(time, "Increment", Config.INCREMENT_SECONDS, s.warnings);

    auto unit = "Time_Unit" in time;
    if (unit !is null && *unit != "1sec") {
        s.warnings ~= format("Time_Unit:%s is not supported; treated as 1sec", *unit);
    }
    return s;
}


private long readSeconds(const string[string] time, string key, long defaultValue, ref string[] warnings)
{
    auto v = key in time;
    if (v !is null) {
        try {
            return to!long(*v);
        } catch (ConvException e) {
            warnings ~= format("%s:%s is not an integer; using default %d", key, *v, defaultValue);
            return defaultValue;
        }
    }
    warnings ~= format("%s is missing; using default %d", key, defaultValue);
    return defaultValue;
}


/**
 * CSA形式の指し手行か（"+7776FU" または "+7776FU,T12"）
 */
bool isMoveLine(string line)
{
    return !line.matchFirst(r"^[+-]\d{4}[A-Z]{2}(,T\d+)?$").empty;
}


/**
 * 指し手行を指した側
 */
color_t moverOf(string line)
{
    return line[0] == '+' ? Color.BLACK : Color.WHITE;
}


/**
 * 指し手行の消費時間（秒）。",T" が無ければ 0
 */
long consumedSeconds(string line)
{
    auto m = line.matchFirst(r",T(\d+)$");
    return m.empty ? 0 : to!long(m[1]);
}


/**
 * 自分の残り時間
 *
 * 自分の手番が来たら startTurn() で加算し、自分の指し手が返ってきたら consume() で消費時間を引く。
 */
struct GameClock
{
    color_t us;
    long remainingMillis;
    long incrementMillis;

    this(color_t us, long totalSeconds, long incrementSeconds)
    {
        this.us = us;
        this.remainingMillis = (totalSeconds - 1) * 1000; // 残り時間が0秒になると時間切れなので、1秒引いておく
        this.incrementMillis = incrementSeconds * 1000;
    }

    /// 自分の手番が来た
    void startTurn()
    {
        remainingMillis += incrementMillis;
    }

    /// 指し手が指された（自分の手なら消費時間を引く）
    void consume(string line)
    {
        if (moverOf(line) == us) {
            remainingMillis -= consumedSeconds(line) * 1000; // 秒 -> ミリ秒
        }
    }

    /// 初期指し手を反映する（再生中は探索しないので、自分の手ごとに加算してから引く）
    void replay(const string[] moves)
    {
        foreach (line; moves) {
            if (moverOf(line) == us) startTurn();
            consume(line);
        }
    }
}


version(unittest)
{
    private string[] summaryLines(string yourTurn, string timeBlock, string[] moves)
    {
        string[] lines = [
            "BEGIN Game_Summary",
            "Protocol_Version:1.2",
            "Protocol_Mode:Server",
            "Format:Shogi 1.0",
            "Declaration:Jishogi 1.1",
            "Game_ID:test",
            "Name+:a",
            "Name-:b",
            "Your_Turn:" ~ yourTurn,
            "Rematch_On_Draw:NO",
            "To_Move:+",
            "Max_Moves:512",
        ];
        import std.array : split;
        lines ~= timeBlock.split("\n");
        lines ~= [
            "BEGIN Position",
            "P1-KY-KE-GI-KI-OU-KI-GI-KE-KY",
            "P2 * -HI *  *  *  *  * -KA * ",
            "P3-FU-FU-FU-FU-FU-FU-FU-FU-FU",
            "P4 *  *  *  *  *  *  *  *  * ",
            "P5 *  *  *  *  *  *  *  *  * ",
            "P6 *  *  *  *  *  *  *  *  * ",
            "P7+FU+FU+FU+FU+FU+FU+FU+FU+FU",
            "P8 * +KA *  *  *  *  * +HI * ",
            "P9+KY+KE+GI+KI+OU+KI+GI+KE+KY",
            "+",
        ];
        lines ~= moves;
        lines ~= ["END Position", "END Game_Summary"];
        return lines;
    }

    private enum TIME_600_2 = "BEGIN Time\nTime_Unit:1sec\nTotal_Time:600\nByoyomi:0\nIncrement:2\nLeast_Time_Per_Move:0\nEND Time";
    private immutable string[] BUOY_420 = ["+5958OU,T422", "-5152OU,T2", "+5859OU,T2", "-5251OU,T2"];
    private immutable string[] BUOY_300 = ["+5958OU,T302", "-5152OU,T2", "+5859OU,T2", "-5251OU,T2"];
}

// 電竜戦7 blackbid420（先手3分・後手10分、2秒加算）: 先手
unittest
{
    auto s = parseGameSummary(summaryLines("+", TIME_600_2, BUOY_420.dup));
    assert(s.us == Color.BLACK);
    assert(s.totalSeconds == 600);
    assert(s.incrementSeconds == 2);
    assert(s.initialMoves == BUOY_420);
    assert(s.warnings.length == 0);
    assert(s.fields["Max_Moves"] == "512");

    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 179_000);
    c.startTurn();
    assert(c.remainingMillis == 181_000);
}

// 電竜戦7 blackbid420: 後手
unittest
{
    auto s = parseGameSummary(summaryLines("-", TIME_600_2, BUOY_420.dup));
    assert(s.us == Color.WHITE);
    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 599_000);
}

// 電竜戦4 blackbid300: 先手
unittest
{
    auto s = parseGameSummary(summaryLines("+", TIME_600_2, BUOY_300.dup));
    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 299_000);
}

// 初期指し手なし（test+default-1500-0）
unittest
{
    auto s = parseGameSummary(summaryLines("-",
        "BEGIN Time\nTime_Unit:1sec\nTotal_Time:1500\nByoyomi:0\nIncrement:0\nLeast_Time_Per_Move:0\nEND Time", []));
    assert(s.totalSeconds == 1500);
    assert(s.incrementSeconds == 0);
    assert(s.initialMoves.length == 0);
    assert(s.warnings.length == 0);
    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 1_499_000);
}

// Increment が無い / 整数でない / Time_Unit が 1sec 以外
unittest
{
    auto s = parseGameSummary(summaryLines("+", "BEGIN Time\nTime_Unit:1sec\nTotal_Time:600\nEND Time", []));
    assert(s.totalSeconds == 600);
    assert(s.incrementSeconds == Config.INCREMENT_SECONDS);
    assert(s.warnings.length == 1);

    s = parseGameSummary(summaryLines("+", "BEGIN Time\nTime_Unit:1min\nTotal_Time:abc\nIncrement:2\nEND Time", []));
    assert(s.totalSeconds == Config.TOTAL_SECONDS);
    assert(s.incrementSeconds == 2);
    assert(s.warnings.length == 2);
}

// BEGIN Time+ / BEGIN Time- の中身は BEGIN Time として読まない
unittest
{
    auto s = parseGameSummary(summaryLines("+",
        "BEGIN Time+\nTotal_Time:180\nEND Time+\nBEGIN Time-\nTotal_Time:600\nEND Time-", []));
    assert(s.totalSeconds == Config.TOTAL_SECONDS);
}

// 指し手行の判定と消費時間
unittest
{
    assert(isMoveLine("+5958OU,T422"));
    assert(isMoveLine("-3334FU"));
    assert(!isMoveLine("P1-KY-KE-GI-KI-OU-KI-GI-KE-KY"));
    assert(!isMoveLine("+"));
    assert(consumedSeconds("+5958OU,T422") == 422);
    assert(consumedSeconds("-3334FU") == 0);
    assert(moverOf("-3334FU") == Color.WHITE);
}

// 奇数手の初期指し手: 先手の手は加算してから消費を引く
unittest
{
    auto c = GameClock(Color.BLACK, 600, 2);
    c.replay(["+7776FU,T5"]);
    assert(c.remainingMillis == 596_000);
}
