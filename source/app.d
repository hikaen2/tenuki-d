import types;
import text;
import player;
import position;
import movegen;
import std.conv;
import std.format;
import std.regex;
import std.socket;
import std.stdio;
import undead.socketstream;

void main_()
{
    // Position p = createPosition("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1");
    // stdout.writeln(p.toString());
    // move_t[600] moves;
    // for (int i = 0; i < 1000000; i++) {
    //     p.legalMoves(moves);
    // }

    Position p = createPosition("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1");
    stdout.writeln(p.toString());
    ponder(p);

}


int main(string[] args)
{
    if (args.length < 5) {
        stderr.writeln("Usage: tenuki host port username password");
        return 1;
    }
    const string host = args[1];
    const string port = args[2];
    const string username = args[3];
    const string password = args[4];
    stdout.writefln("Connecting to %s port %s.", host, port);
    Socket sock = new TcpSocket(new InternetAddress(host, to!ushort(port)));
    scope(exit) sock.close();

    SocketStream s = new SocketStream(sock);
    writeLine(s, format("LOGIN %s %s", username, password));
    const side_t mySide = (readLineUntil(s, regex("Your_Turn:(\\+|-)")).front[1] == "+" ? Side.BLACK : Side.WHITE);
    readLineUntil(s, regex("END Game_Summary"));
    writeLine(s, "AGREE");
    readLineUntil(s, regex("START"));

    Position p = createPosition("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    stdout.writeln(p.toString());

    for (;;) {
        if (p.sideToMove == mySide) {
            writeLine(s, ponder(p).toString(p));
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
