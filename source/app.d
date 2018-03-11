import types;
import text;
import player;
import position;
import std.conv;
import std.format;
import std.regex;
import std.socket;
import std.stdio;
import undead.socketstream;

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
    Socket sock = new TcpSocket(new InternetAddress("localhost", 4081));
    scope(exit) sock.close();

    SocketStream s = new SocketStream(sock);
    s.writeLine(format("LOGIN %s %s", username, password));
    const side_t mySide = (s.readLineUntil(regex("Your_Turn:(\\+|-)")).front[1] == "+" ? Side.BLACK : Side.WHITE);
    s.readLineUntil(regex("END Game_Summary"));
    s.writeLine("AGREE");
    s.readLineUntil(regex("START"));

    Position p = createPosition("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    stdout.writeln(p.toString());

    for (;;) {
        if (p.sideToMove == mySide) {
            s.writeLine(ponder(p).toString(p));
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

    /*

    if (side == "-") {
        s.readLine();
    }

    s.writeLine("%TORYO");
    s.readLineUntil(regex("#LOSE|#WIN|#DRAW"));

    writeln("Edit source/app.d to start your project.");
    */

}

private string readLine(ref SocketStream s)
{
    string str = to!string(s.readLine());
    stderr.writeln(str);
    return str;
}

private RegexMatch!string readLineUntil(ref SocketStream s, Regex!char re)
{
    RegexMatch!string m;
    for (string str = readLine(s); (m = str.match(re)).empty; str = readLine(s)) {}
    return m;
}
