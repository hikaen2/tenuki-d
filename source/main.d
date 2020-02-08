import book;
import core.thread;
import movegen;
import parser;
import position;
import search;
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
static import config, misc, tt;


__gshared private Socket SOCKET;
__gshared private bool USE_ENHANCED_CSA_PROTOCOL = false;
__gshared private File RECV_LOG;


int main(string[] args)
{
    // info
    stdout.writeln(tt.info());

    if (args.length >= 2 && args[1] == "test") {
        test();
        return 0;
    }
    if (args.length >= 2 && args[1] == "validate") {
        validateBook();
        return 0;
    }

    ushort port = 4081;
    try {
        getopt(args, "e", &USE_ENHANCED_CSA_PROTOCOL, "p", &port);
        if (args.length < 4) {
            throw new Exception("");
        }
    } catch (Exception e) {
        stderr.writeln("usage: tenuki [-e] [-p port] hostname username password");
        stderr.writeln("  -e  send enhanced CSA protocol");
        stderr.writeln("  -p  default: 4081");
        return 1;
    }
    const string hostname = args[1];
    const string username = args[2];
    const string password = args[3];

    stdout.writefln("Connecting to %s port %s.", hostname, port);
    SOCKET = new TcpSocket(new InternetAddress(hostname, port));
    scope(exit) SOCKET.close();
    SOCKET.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(3600));

    {
        SysTime now = Clock.currTime();
        now.fracSecs(Duration.zero());
        RECV_LOG = File(format("log/%s.log", now.toISOString()), "w");
    }
    scope(exit) RECV_LOG.close();

    SOCKET.writeLine(format("LOGIN %s %s", username, password));
    if (SOCKET.readLine() == "LOGIN:incorrect") {
        return 1;
    }

    string[string] gameSummary;
    for (string line = SOCKET.readLine(); line != "END Game_Summary"; line = SOCKET.readLine()) {
        auto m = line.matchFirst(r"^([^:]+):(.+)$");
        if (!m.empty) {
            gameSummary[m[1]] = m[2];
        }
    }

    const color_t us = (gameSummary["Your_Turn"] == "+" ? Color.BLACK : Color.WHITE);
    SOCKET.writeLine("AGREE");
    if (!SOCKET.readLine().matchFirst("^START:")) {
        return 1;
    }

    return csaloop(us);
}


int csaloop(const color_t us)
{
    Position p = parsePosition("sfen lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    stdout.writeln(p.toString());

    if (us == Color.BLACK) {
        search.REMAIN_SECONDS += config.INCREMENT_SECONDS;
        new SearchThread(p).start(); // search & send
    }

    for (;;) {
        const string line = SOCKET.readLine();

        if (line.matchFirst(r"^(\+|-)\d{4}\D{2},T\d+$")) {

            if (p.sideToMove == us) {
                search.REMAIN_SECONDS -= to!int(line.matchFirst(r",T(\d+)")[1]);
            }

            p = p.doMove(parseMove(line, p));
            stderr.writeln(toString(p));
            stderr.writeln(search.REMAIN_SECONDS);
            if (p.sideToMove == us) {
                search.REMAIN_SECONDS += config.INCREMENT_SECONDS;
                new SearchThread(p).start(); // search & send
            }

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
    stdout.writefln("stored: %12d", tt.stat_stored);
    stdout.writefln("nothing:%12d", tt.stat_nothing);
    stdout.writefln("hit:    %12d", tt.stat_hit);
    stdout.writefln("misshit:%12d", tt.stat_misshit);

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
