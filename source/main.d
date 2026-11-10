module main;

import book;
import core.thread;
import movegen;
import parser;
import position;
import search;
import settings;
import std.algorithm.comparison;
import std.conv;
import std.datetime.systime : SysTime, Clock;
import std.format;
import std.getopt;
import std.regex;
import std.socket;
import std.stdio;
import text;
import types;
import config;
import csa;
import tt;
static import misc;


__gshared private Socket SOCKET;
__gshared private bool USE_ENHANCED_CSA_PROTOCOL = false;
__gshared private File RECV_LOG;


int main(string[] args)
{
    ushort port = 4081;
    string settingsPath = null;
    try {
        getopt(args, "e", &USE_ENHANCED_CSA_PROTOCOL, "p", &port, "c", &settingsPath);
    } catch (Exception e) {
        usage();
        return 1;
    }

    // 設定を読んでから、置換表と探索スレッドを確保する
    try {
        const EngineSettings s = (settingsPath is null)
            ? loadSettings("tenuki.conf", false)
            : loadSettings(settingsPath, true);
        stdout.writefln("settings: %s (hash_mb = %d, threads = %d)",
            s.source == EngineSettings.DEFAULT_SOURCE ? "defaults (tenuki.conf not found)" : s.source,
            s.hashMb, s.threads);
        stdout.flush();
        tt_init(s.hashMb);
        search_init(s.threads);
        stdout.writefln("%s, %d threads", tt_info(), s.threads);
    } catch (Exception e) {
        stderr.writefln("error: %s", e.msg);
        return 1;
    }

    if (args.length >= 2 && args[1] == "test") {
        test();
        return 0;
    }
    if (args.length >= 2 && args[1] == "validate") {
        validateBook();
        return 0;
    }

    if (args.length < 4) {
        usage();
        return 1;
    }
    const string hostname = args[1];
    const string username = args[2];
    const string password = args[3];

    stdout.writefln("Connecting to %s port %s.", hostname, port);
    SOCKET = new TcpSocket(new InternetAddress(hostname, port));
    scope(exit) SOCKET.close();
    SOCKET.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(3600));

    RECV_LOG = File(format("log/%s.log", Clock.currTime().apply((ref SysTime it) => it.fracSecs = hnsecs(0)).toISOString()), "w");
    scope(exit) RECV_LOG.close();

    SOCKET.writeLine(format("LOGIN %s %s", username, password));
    if (SOCKET.readLine() == "LOGIN:incorrect") {
        return 1;
    }

    string[] summaryLines;
    for (string line = SOCKET.readLine(); line != "END Game_Summary"; line = SOCKET.readLine()) {
        summaryLines ~= line;
    }
    const GameSummary summary = parseGameSummary(summaryLines);
    foreach (w; summary.warnings) {
        stderr.writefln("warning: %s", w);
    }

    // 開始局面は平手。BEGIN Position 内の指し手（ブイ）を局面と時計に反映する
    Position p = parsePosition("sfen lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    GameClock clock = GameClock(summary.us, summary.totalSeconds, summary.incrementSeconds);
    clock.replay(summary.initialMoves);
    foreach (line; summary.initialMoves) {
        p = p.doMove(parseMove(line, p));
    }
    stderr.writefln("time: total %d seconds, increment %d seconds, remaining %d seconds after %d initial moves.",
        summary.totalSeconds, summary.incrementSeconds, clock.remainingMillis / 1000, summary.initialMoves.length);

    SOCKET.writeLine("AGREE");
    if (!SOCKET.readLine().matchFirst("^START:")) {
        return 1;
    }

    return csaloop(summary.us, p, clock);
}


private void usage()
{
    stderr.writeln("usage: tenuki [-c file] [-e] [-p port] hostname username password");
    stderr.writeln("       tenuki [-c file] test|validate");
    stderr.writeln("  -c  settings file (default: tenuki.conf in the current directory)");
    stderr.writeln("  -e  send enhanced CSA protocol");
    stderr.writeln("  -p  default: 4081");
}


int csaloop(const color_t us, Position p, GameClock clock)
{
    stdout.writeln(p.toString());

    // 手番が自分なら加算して探索を始める
    void startTurnIfOurs()
    {
        if (p.sideToMove == us) {
            clock.startTurn();
            search.RemainingMillis = clock.remainingMillis;
            new SearchThread(p).start(); // search & send
        }
    }

    startTurnIfOurs();

    for (;;) {
        const string line = SOCKET.readLine();

        if (line.matchFirst(r"^(\+|-)\d{4}\D{2},T\d+$")) {

            clock.consume(line);
            p = p.doMove(parseMove(line, p));
            stderr.writeln(toString(p));
            stderr.writefln("%d seconds.", clock.remainingMillis / 1000); // ミリ秒 -> 秒
            startTurnIfOurs();

        } else if (line.matchFirst(r"^%TORYO(,T\d+)?$") || line.matchFirst(r"^%KACHI(,T\d+)?$")) {

            // do nothing

        } else if (line.among("#ILLEGAL_ACTION", "#ILLEGAL_MOVE", "#JISHOGI", "#MAX_MOVES", "#OUTE_SENNICHITE", "#RESIGN", "#SENNICHITE", "#TIME_UP")) {

            // do nothing

        } else if (line.among("#WIN", "#LOSE", "#DRAW", "#CENSORED", "#CHUDAN")) {

            SOCKET.writeLine("LOGOUT");
            return 0;

        } else if (line == "") {

            /*
             * see http://www2.computer-shogi.org/protocol/tcp_ip_server_121.html
             * > クライアントは対局中、手番にかかわらず、長さゼロの文字列、もしくはLF1文字のみをサーバに送信することができる。
             * > サーバは前者を受け取った場合、単純に無視する。後者を受け取った場合、短い待ち時間の後にLF1文字のみをそのクライアントに返信する。
             */

        } else {

            stderr.writefln("unknown command: '%s'", line);

        }
    }
}


class SearchThread : Thread
{
    private Position p;

    this(Position p)
    {
        this.p = p;
        super(&run);
    }

    private void run()
    {
        Move[64] pv;
        int score = p.ponder(pv);
        if (pv[0] == Move.TORYO) {
            SOCKET.writeLine(pv[0].toString(p));
        } else if (USE_ENHANCED_CSA_PROTOCOL) {
            SOCKET.writeLine(format("%s,'* %d %s", pv[0].toString(p), (p.sideToMove == Color.BLACK ? score : -score), pv.toString(p, 1)));
        } else {
            SOCKET.writeLine(format("%s", pv[0].toString(p)));
        }
    }
}


private void test()
{
    // Position p = parsePosition("sfen l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1");
    // stdout.writeln(p.toString());
    // Move[600] moves;
    // for (int i = 0; i < 1000000; i++) {
    //     p.legalMoves(moves);
    // }

    Position p = parsePosition("sfen l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1"); // 指し手生成祭り
    //Position p = parsePosition("sfen kn6l/3g2r2/sGp2s3/lp1pp4/2N2ppl1/2P1P4/2NS1PP1+p/3GKS3/+b3G2+rL b Pbn6p 1"); // 打ち歩詰め局面
    //Position p = parsePosition("sfen lnsgkgsnl/1r5b1/p1ppppppp/9/1p7/9/PPPPPPPPP/1B4KR1/LNSG1GSNL b - 0"); // test+default-1500-0+tenuki+neakih+20180403232658
    writeln(p.sizeof);
    stdout.writeln(p.toString());
    Move[64] pv;
    p.ponder(pv);
    //stdout.writefln("stored: %12d", tt.stat_stored);
    //stdout.writefln("nothing:%12d", tt.stat_nothing);
    //stdout.writefln("hit:    %12d", tt.stat_hit);
    //stdout.writefln("misshit:%12d", tt.stat_misshit);

    // Position p = parsePosition("sfen 9/9/9/9/9/9/9/9/P8 b - 1");
    // stdout.writeln(p.toString());
    // p = p.doMove(parseMove("+9998FU", p));
    // stdout.writeln(p.toString());
}


/**
 * ソケットに文字列を書き込む
 */
private void writeLine(ref Socket s, string str)
{
    misc.writeln(s, str);
    stderr.writefln(">\"%s\\n\"", str);
}


/**
 * ソケットから１行読み込む
 */
private string readLine(ref Socket s)
{
    string line = misc.readln(s);
    stderr.writefln("<\"%s\\n\"", line);
    RECV_LOG.writeln(line);
    RECV_LOG.flush();
    return line;
}


/**
 * ソケットからパターンに一致するまで行を読む
 */
private Captures!string readLineUntil(ref Socket s, string re)
{
    Captures!string m;
    for (string str = s.readLine(); (m = str.matchFirst(re)).empty; str = s.readLine()) {}
    return m;
}


/**
 * see https://kotlinlang.org/api/latest/jvm/stdlib/kotlin/apply.html
 */
T apply(T)(T it, void function(ref T) action) {
    action(it);
    return it;
}
