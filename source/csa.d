module csa;

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
    string[] warnings;              /// 未対応の値だった、などの警告
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

    s.totalSeconds = readSeconds(time, "Total_Time");
    s.incrementSeconds = readSeconds(time, "Increment");

    auto unit = "Time_Unit" in time;
    if (unit !is null && *unit != "1sec") {
        s.warnings ~= format("Time_Unit:%s is not supported; treated as 1sec", *unit);
    }
    return s;
}


private long readSeconds(const string[string] time, string key)
{
    auto v = key in time;
    if (v is null) {
        throw new Exception(format("Game_Summary: %s is missing in BEGIN Time", key));
    }
    long n;
    try {
        n = to!long(*v);
    } catch (ConvException e) {
        throw new Exception(format("Game_Summary: %s:%s is not an integer", key, *v));
    }
    if (n < 0) {
        throw new Exception(format("Game_Summary: %s:%s is negative", key, *v));
    }
    return n;
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
    long searchMillis;      /// 1手の探索時間（planMoves で決める）

    this(color_t us, long totalSeconds, long incrementSeconds)
    {
        this.us = us;
        // 通信の遅れで時間切れにならないよう、持ち時間から TIME_MARGIN_SECONDS 引いておく
        this.remainingMillis = (totalSeconds > TIME_MARGIN_SECONDS ? totalSeconds - TIME_MARGIN_SECONDS : 0) * 1000;
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

    /// 今の残り時間を moves 手で使い切るように、1手の探索時間を決める（対局開始時に1回呼ぶ）
    void planMoves(int moves)
    {
        searchMillis = remainingMillis / moves + incrementMillis;
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


/// 通信の遅れに備えて、持ち時間からこの秒数を引いておく
enum TIME_MARGIN_SECONDS = 10;


/// 対局開始時の残り時間を、この手数で使い切るように1手の探索時間を決める
enum MOVES_TO_USE_UP = 60;


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
    assert(c.remainingMillis == 170_000);
    c.startTurn();
    assert(c.remainingMillis == 172_000);
}

// 電竜戦7 blackbid420: 後手
unittest
{
    auto s = parseGameSummary(summaryLines("-", TIME_600_2, BUOY_420.dup));
    assert(s.us == Color.WHITE);
    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 590_000);
}

// 電竜戦4 blackbid300: 先手
unittest
{
    auto s = parseGameSummary(summaryLines("+", TIME_600_2, BUOY_300.dup));
    auto c = GameClock(s.us, s.totalSeconds, s.incrementSeconds);
    c.replay(s.initialMoves);
    assert(c.remainingMillis == 290_000);
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
    assert(c.remainingMillis == 1_490_000);
}

version(unittest)
{
    private bool throws(lazy GameSummary e)
    {
        try {
            e();
        } catch (Exception ex) {
            return true;
        }
        return false;
    }
}

// Total_Time / Increment が無い・整数でない → 例外
unittest
{
    assert(throws(parseGameSummary(summaryLines("+", "BEGIN Time\nTime_Unit:1sec\nTotal_Time:600\nEND Time", []))));
    assert(throws(parseGameSummary(summaryLines("+", "BEGIN Time\nTotal_Time:abc\nIncrement:2\nEND Time", []))));
    assert(throws(parseGameSummary(summaryLines("+", "BEGIN Time\nTotal_Time:-1\nIncrement:2\nEND Time", []))));
}

// Time_Unit が 1sec 以外 → 警告
unittest
{
    auto s = parseGameSummary(summaryLines("+", "BEGIN Time\nTime_Unit:1min\nTotal_Time:10\nIncrement:0\nEND Time", []));
    assert(s.totalSeconds == 10);
    assert(s.warnings.length == 1);
}

// BEGIN Time+ / BEGIN Time- の中身は BEGIN Time として読まない
unittest
{
    assert(throws(parseGameSummary(summaryLines("+",
        "BEGIN Time+\nTotal_Time:180\nIncrement:2\nEND Time+\nBEGIN Time-\nTotal_Time:600\nIncrement:2\nEND Time-", []))));
}

// 探索時間の配分: 対局開始時の残り時間を60手で使い切る
unittest
{
    // 電竜戦7 先手（3分+2秒）: ブイ反映後の残り170秒 → 170000/60 + 2000 = 4,833ms
    auto c = GameClock(Color.BLACK, 600, 2);
    c.replay(["+5958OU,T422", "-5152OU,T2", "+5859OU,T2", "-5251OU,T2"]);
    c.planMoves(MOVES_TO_USE_UP);
    assert(c.searchMillis == 4_833);

    // 電竜戦7 後手（10分+2秒）: 残り590秒 → 590000/60 + 2000 = 11,833ms
    c = GameClock(Color.WHITE, 600, 2);
    c.replay(["+5958OU,T422", "-5152OU,T2", "+5859OU,T2", "-5251OU,T2"]);
    c.planMoves(MOVES_TO_USE_UP);
    assert(c.searchMillis == 11_833);

    // 1手の探索時間は対局中に変わらない
    c.startTurn();
    c.consume("-3334FU,T12");
    c.startTurn();
    assert(c.searchMillis == 11_833);
}

// 持ち時間が余裕の秒数以下なら残り時間は0（負にしない）
unittest
{
    auto c = GameClock(Color.BLACK, 5, 1);
    assert(c.remainingMillis == 0);
    c.planMoves(MOVES_TO_USE_UP);
    assert(c.searchMillis == 1_000);
    c = GameClock(Color.BLACK, 60, 1);
    assert(c.remainingMillis == 50_000);
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
    assert(c.remainingMillis == 587_000);
}
