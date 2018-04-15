import types;
import text;
import player;
import position;
import movegen;
import parser;
import std.conv;
import std.format;
import std.getopt;
import std.regex;
import std.socket;
import std.stdio;
import undead.socketstream;

void test()
{
    // Position p = parsePosition("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1");
    // stdout.writeln(p.toString());
    // move_t[600] moves;
    // for (int i = 0; i < 1000000; i++) {
    //     p.legalMoves(moves);
    // }

    Position p = parsePosition("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1"); // 指し手生成祭り
    //Position p = parsePosition("kn6l/3g2r2/sGp2s3/lp1pp4/2N2ppl1/2P1P4/2NS1PP1+p/3GKS3/+b3G2+rL b Pbn6p 1"); // 打ち歩詰め局面
    //Position p = parsePosition("lnsgkgsnl/1r5b1/p1ppppppp/9/1p7/9/PPPPPPPPP/1B4KR1/LNSG1GSNL b - 0"); // test+default-1500-0+tenuki+neakih+20180403232658
    writeln(p.sizeof);
    stdout.writeln(p.toString());
    move_t[64] pv;
    p.ponder(pv);

    // Position p = parsePosition("9/9/9/9/9/9/9/9/P8 b - 1");
    // stdout.writeln(p.toString());
    // p = p.doMove(parseMove("+9998FU", p));
    // stdout.writeln(p.toString());
}

void printUsage() {
    stderr.writeln("usage: tenuki [-e] [-p port] hostname username password");
    stderr.writeln("  -e  send enhanced CSA protocol");
    stderr.writeln("  -p  default: 4081");
}

int main(string[] args)
{
    if (args.length >= 2 && args[1] == "test") {
        test();
        return 0;
    }

    bool enhanced = false;
    ushort port = 4081;
    try {
        getopt(args, "e", &enhanced, "p", &port);
    } catch (Exception e) {
        printUsage();
        return 1;
    }
    if (args.length < 4) {
        printUsage();
        return 1;
    }
    const string host = args[1];
    const string username = args[2];
    const string password = args[3];
    stdout.writefln("Connecting to %s port %s.", host, port);
    Socket sock = new TcpSocket(new InternetAddress(host, port));
    scope(exit) sock.close();

    SocketStream s = new SocketStream(sock);
    writeLine(s, format("LOGIN %s %s", username, password));
    const side_t mySide = (readLineUntil(s, regex("Your_Turn:(\\+|-)")).front[1] == "+" ? Side.BLACK : Side.WHITE);
    readLineUntil(s, regex("END Game_Summary"));
    writeLine(s, "AGREE");
    readLineUntil(s, regex("START"));

    Position p = parsePosition("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    stdout.writeln(p.toString());

    for (;;) {
        if (p.sideToMove == mySide) {
            move_t[64] pv;
            int score = p.ponder(pv);
            string wk;
            {
                Position q = p.doMove(pv[0]);
                for (int i = 1; pv[i] != 0; i++) {
                    wk ~= format("%s ", pv[i].toString(q));
                    q = q.doMove(pv[i]);
                }
            }
            if (pv[0] == Move.TORYO) {
                writeLine(s, pv[0].toString(p));
            } else if (enhanced) {
                writeLine(s, format("%s,'* %d %s", pv[0].toString(p), (p.sideToMove == Side.BLACK ? score : -score), wk));
            } else {
                writeLine(s, format("%s", pv[0].toString(p)));
            }
        }

        move_t m;
        for (bool retry = true; retry; ) {
            try {
                string line = readLine(s);
                if (line == "#LOSE" || line == "#WIN" || line == "#DRAW" || line == "#CENSORED") {
                    return 0;
                }
                m = parseMove(line, p);
                retry = false;
            } catch (Exception e) {
                retry = true;
            }
        }
        stderr.writeln(toString(m, p));
        p = p.doMove(m);
        stderr.writeln(toString(p));

    }
}

private void writeLine(ref SocketStream s, string str)
{
    s.writeLine(str);
    stderr.writeln(format(">%s", str));
}

private string readLine(ref SocketStream s)
{
    string str = to!string(s.readLine());
    stderr.writeln(str);
    if (str == "") {
        throw new Exception("connection lost");
    }
    return str;
}

private RegexMatch!string readLineUntil(ref SocketStream s, Regex!char re)
{
    RegexMatch!string m;
    for (string str = readLine(s); (m = str.match(re)).empty; str = readLine(s)) {}
    return m;
}
