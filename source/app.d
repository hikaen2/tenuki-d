import std.stdio;
import std.socket;
import std.regex;
import std.conv;
import undead.socketstream;

void main()
{

    Socket sock = new TcpSocket(new InternetAddress("localhost", 4081));
    scope(exit) sock.close();

    SocketStream s = new SocketStream(sock);
    s.writeLine("LOGIN name password");
    string side = s.readLineUntil(regex("Your_Turn:(\\+|-)")).front[1];
    s.readLineUntil(regex("END Game_Summary"));

    s.writeLine("AGREE");
    s.readLineUntil(regex("START"));

    if (side == "-") {
        s.readLine();
    }

    s.writeLine("%TORYO");
    s.readLineUntil(regex("#LOSE|#WIN|#DRAW"));

    writeln("Edit source/app.d to start your project.");
}

private RegexMatch!string readLineUntil(ref SocketStream s, Regex!char re)
{
    string readLine(ref SocketStream s)
    {
        string str = to!string(s.readLine());
        stderr.writeln(str);
        return str;
    }
    RegexMatch!string m;
    for (string str = readLine(s); (m = str.match(re)).empty; str = readLine(s)) {}
    return m;
}
