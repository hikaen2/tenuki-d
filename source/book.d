import types;
import parser;
import text;
import movegen;
import std.stdio;
import std.string;
import std.regex;

move_t[][string] BOOK;;

static this()
{
    File f = File("kick.txt", "r");
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

    // foreach (key, value; BOOK) {
    //     writeln(key);
    //     foreach (move; value) {
    //         writeln(move);
    //     }
    // }
}

void validateBook()
{
    foreach (sfen, moves; BOOK) {
        Position p = parsePosition(sfen);
        assert(sfen == p.toSfen);
        foreach (move_t move; moves) {
            if (!move.isValid(p)) {
                stderr.writeln(p.toString);
                stderr.writefln("%02d%02d", (move >> 7) & 0b1111111, move & 0b1111111);
            }
        }
    }
}

/*
 * 7g7f
 * 8h2b+
 * G*5b
 */
private move_t parseUsi(string usi)
{
    immutable type_t[string] TYPE = [
        "P":Type.PAWN, "L":Type.LANCE, "N":Type.KNIGHT, "S":Type.SILVER, "B":Type.BISHOP, "R":Type.ROOK, "G":Type.GOLD,
    ];

    immutable int[string] ADDRESS = [
        "1a":11, "1b":12, "1c":13, "1d":14, "1e":15, "1f":16, "1g":17, "1h":18, "1i":19,
        "2a":21, "2b":22, "2c":23, "2d":24, "2e":25, "2f":26, "2g":27, "2h":28, "2i":29,
        "3a":31, "3b":32, "3c":33, "3d":34, "3e":35, "3f":36, "3g":37, "3h":38, "3i":39,
        "4a":41, "4b":42, "4c":43, "4d":44, "4e":45, "4f":46, "4g":47, "4h":48, "4i":49,
        "5a":51, "5b":52, "5c":53, "5d":54, "5e":55, "5f":56, "5g":57, "5h":58, "5i":59,
        "6a":61, "6b":62, "6c":63, "6d":64, "6e":65, "6f":66, "6g":67, "6h":68, "6i":69,
        "7a":71, "7b":72, "7c":73, "7d":74, "7e":75, "7f":76, "7g":77, "7h":78, "7i":79,
        "8a":81, "8b":82, "8c":83, "8d":84, "8e":85, "8f":86, "8g":87, "8h":88, "8i":89,
        "9a":91, "9b":92, "9c":93, "9d":94, "9e":95, "9f":96, "9g":97, "9h":98, "9i":99,
    ];

    auto m = usi.matchFirst(r"(\D)\*(\d\D)");
    if (!m.empty) {
        return createDrop(TYPE[m[1]], ADDRESS[m[2]]);
    }

    m = usi.matchFirst(r"(\d\D)(\d\D)(\+?)");
    int from = ADDRESS[m[1]];
    int to = ADDRESS[m[2]];
    bool promote = (m[3] == "+");
    return promote ? createPromote(from, to) : createMove(from, to);
}
