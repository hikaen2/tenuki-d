module book;

import movegen;
import parser;
import std.random;
import std.regex;
import std.stdio;
import std.string;
import text;
import types;


immutable Move[][string] BOOK;


shared static this()
{
    File f = File("book.db", "r");
    scope(exit) f.close();

    string line;
    string key;
    while ((line = f.readln()) !is null) {
        line = line.strip;
        if (line.matchFirst(r"^#")) {
            continue;
        }
        if (line.matchFirst(r"^sfen ")) {
            key = line;
        } else {
            BOOK[key] ~= parseUsi(line);
        }
    }

}


struct BookPos
{
    Move bestMove;
    Move nextMove;
    int value;
    int depth;
    int num;
}


Move pick(const ref Position p)
{
    const string sfen = p.toSfen();
    if (sfen in book.BOOK) {
        return book.BOOK[sfen][ uniform(0, book.BOOK[sfen].length) ];
    }
    return Move.NULL;
}


void dump()
{
    foreach (key, value; BOOK) {
        writeln(key);
        foreach (move; value) {
            writeln(move);
        }
    }
}


void validateBook()
{
    foreach (sfen, moves; BOOK) {
        Position p = parsePosition(sfen);
        assert(sfen == p.toSfen);
        foreach (Move move; moves) {
            if (!move.isValid(p)) {
                stderr.writeln(p.toString);
                stderr.writefln("%02d%02d", (move.i >> 7) & 0b1111111, move.i & 0b1111111);
            }
        }
    }
}


/*
 * 7g7f
 * 8h2b+
 * G*5b
 */
private Move parseUsi(string usi)
{
    immutable type_t[string] TYPE = [
        "P":Type.PAWN, "L":Type.LANCE, "N":Type.KNIGHT, "S":Type.SILVER, "B":Type.BISHOP, "R":Type.ROOK, "G":Type.GOLD,
    ];

    immutable int[string] ADDRESS = [
        "1a": 0, "1b": 1, "1c": 2, "1d": 3, "1e": 4, "1f": 5, "1g": 6, "1h": 7, "1i": 8,
        "2a": 9, "2b":10, "2c":11, "2d":12, "2e":13, "2f":14, "2g":15, "2h":16, "2i":17,
        "3a":18, "3b":19, "3c":20, "3d":21, "3e":22, "3f":23, "3g":24, "3h":25, "3i":26,
        "4a":27, "4b":28, "4c":29, "4d":30, "4e":31, "4f":32, "4g":33, "4h":34, "4i":35,
        "5a":36, "5b":37, "5c":38, "5d":39, "5e":40, "5f":41, "5g":42, "5h":43, "5i":44,
        "6a":45, "6b":46, "6c":47, "6d":48, "6e":49, "6f":50, "6g":51, "6h":52, "6i":53,
        "7a":54, "7b":55, "7c":56, "7d":57, "7e":58, "7f":59, "7g":60, "7h":61, "7i":62,
        "8a":63, "8b":64, "8c":65, "8d":66, "8e":67, "8f":68, "8g":69, "8h":70, "8i":71,
        "9a":72, "9b":73, "9c":74, "9d":75, "9e":76, "9f":77, "9g":78, "9h":79, "9i":80,
    ];

    auto m = usi.matchFirst(r"^(\D)\*(\d\D)");
    if (!m.empty) {
        return createDrop(TYPE[m[1]], ADDRESS[m[2]]);
    }

    m = usi.matchFirst(r"^(\d\D)(\d\D)(\+?)");
    int from = ADDRESS[m[1]];
    int to = ADDRESS[m[2]];
    bool promote = (m[3] == "+");
    return promote ? createPromote(from, to) : createMove(from, to);
}
