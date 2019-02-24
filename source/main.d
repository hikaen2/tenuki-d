import book;
import types;
import text;
import search;
import position;
import movegen;
import parser;
import std.conv;
import std.format;
import std.getopt;
import std.regex;
import std.socket;
import std.stdio;

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

    // Position p = parsePosition("sfen 9/9/9/9/9/9/9/9/P8 b - 1");
    // stdout.writeln(p.toString());
    // p = p.doMove(parseMove("+9998FU", p));
    // stdout.writeln(p.toString());
}

int main(string[] args)
{
    if (args.length >= 2 && args[1] == "test") {
        test();
        return 0;
    }
    if (args.length >= 2 && args[1] == "validate") {
        validateBook();
        return 0;
    }

    bool enhanced = false;
    ushort port = 4081;
    try {
        getopt(args, "e", &enhanced, "p", &port);
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
    Socket s = new TcpSocket(new InternetAddress(hostname, port));
    scope(exit) s.close();

    writeLine(s, format("LOGIN %s %s", username, password));

    string[string] gameSummary;
    for (string line = readLine(s); line != "END Game_Summary"; line = readLine(s)) {
        auto m = line.matchFirst(r"^([^:]+):(.+)$");
        if (!m.empty) {
            gameSummary[m[1]] = m[2];
        }
    }

    const color_t us = (gameSummary["Your_Turn"] == "+" ? Color.BLACK : Color.WHITE);
    writeLine(s, "AGREE");
    readLineUntil(s, "START");

    Position p = parsePosition("sfen lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    stdout.writeln(p.toString());

    for (;;) {
        if (p.sideToMove == us) {
            Move[64] pv;
            int score = p.ponder(pv);
            if (pv[0] == Move.TORYO) {
                writeLine(s, pv[0].toString(p));
            } else if (enhanced) {
                string wk;
                Position q = p.doMove(pv[0]);
                for (int i = 1; pv[i] != Move.NULL; i++) {
                    wk ~= format("%s ", pv[i].toString(q));
                    q = q.doMove(pv[i]);
                }
                writeLine(s, format("%s,'* %d %s", pv[0].toString(p), (p.sideToMove == Color.BLACK ? score : -score), wk));
            } else {
                writeLine(s, format("%s", pv[0].toString(p)));
            }
        }

        Move m;
        int second;
        for (bool retry = true; retry; ) {
            try {
                string line = readLine(s);
                if (line == "#LOSE" || line == "#WIN" || line == "#DRAW" || line == "#CENSORED") {
                    return 0;
                }
                m = parseMove(line, p);
                second = to!int(line.matchFirst(r",T(\d+)")[1]);
                retry = false;
            } catch (Exception e) {
                retry = true;
            }
        }
        if (p.sideToMove == us) {
            search.remainSeconds -= second;
        }
        stderr.writeln(toString(m, p));
        p = p.doMove(m);
        stderr.writeln(toString(p));
        stderr.writeln(search.remainSeconds);
    }
}

/**
 * ソケットに文字列を書き込む
 */
private void writeLine(ref Socket s, string str)
{
    s.send(str ~ "\n");
    stderr.writeln(format(">%s", str));
}

/**
 * ソケットから１行読み込む
 */
private string readLine(ref Socket s)
{
    string line;
    char[1] c;
    for (auto len = s.receive(c); c[0] != '\n'; len = s.receive(c)) {
        if (len == 0) {
            throw new Exception("connection lost");
        }
        line ~= c;
    }
    stderr.writeln(line);
    RecvLog.writeln(line);
    RecvLog.flush();
    return line;
}

/**
 * ソケットからパターンに一致するまで行を読む
 */
private Captures!string readLineUntil(ref Socket s, string re)
{
    Captures!string m;
    for (string str = readLine(s); (m = str.matchFirst(re)).empty; str = readLine(s)) {}
    return m;
}

private File RecvLog;

static this() {
    RecvLog = File("recv.log", "w");
}

static ~this() {
    RecvLog.close();
}
