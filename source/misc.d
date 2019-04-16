module misc;

import std.socket;
import std.stdio;

/**
 * ソケットに文字列を書き込む
 */
void writeln(ref Socket s, string str)
{
    s.send(str ~ "\n");
}


/**
 * ソケットから１行読み込む
 */
string readln(ref Socket s)
{
    string line;
    char[1] c;
    for (auto len = s.receive(c); c[0] != '\n'; len = s.receive(c)) {
        if (len == -1) {
            throw new Exception("recv timeout");
        }
        if (len == 0) {
            throw new Exception("connection lost");
        }
        line ~= c;
    }
    return line;
}
