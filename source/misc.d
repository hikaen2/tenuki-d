module misc;


import std.algorithm.iteration;
import std.socket;
import std.stdio;
import std.random;
import core.stdc.errno;

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
        if (len == Socket.ERROR) {
            if (errno() == EAGAIN) {
                throw new Exception("recv timed out");
            }
            continue;
        }
        if (len == 0) {
            throw new Exception("connection lost");
        }
        line ~= c;
    }
    return line;
}


int weightedRandom(int[] weights)
{
    const int sum = weights.sum();
    int value = uniform(1, sum + 1);
    for (int i = 0; i < weights.length; i++) {
        if (weights[i] >= value) {
            return i;
        }
        value -= weights[i];
    }
    return -1;
}
