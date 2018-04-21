import types;
import hash_seed;
import std.array;
import std.ascii;
import std.conv;
import std.regex;
import std.string;

move_t parseMove(string s, const ref Position p)
{
    immutable type_t[string] DIC = [
        "FU": Type.PAWN,
        "KY": Type.LANCE,
        "KE": Type.KNIGHT,
        "GI": Type.SILVER,
        "KI": Type.GOLD,
        "KA": Type.BISHOP,
        "HI": Type.ROOK,
        "OU": Type.KING,
        "TO": Type.PROMOTED_PAWN,
        "NY": Type.PROMOTED_LANCE,
        "NK": Type.PROMOTED_KNIGHT,
        "NG": Type.PROMOTED_SILVER,
        "UM": Type.PROMOTED_BISHOP,
        "RY": Type.PROMOTED_ROOK,
    ];

    auto m = s.matchFirst(r"(-|\+)(\d{2})(\d{2})(\w{2})");
    int from = to!int(m[2]);
    int to = to!int(m[3]);
    type_t t = DIC[m[4]];

    if (from == 0) {
        return createDrop(t, to); // fromが0なら駒打ち
    } else if (t != p.squares[from].type()) {
        return createPromote(from, to); // 成る
    } else {
        return createMove(from, to);
    }
}

Position parsePosition(string sfen)
{
    immutable square_t[string] TO_SQUARE = [
        "1":  Square.EMPTY,
        "P":  Square.B_PAWN,
        "L":  Square.B_LANCE,
        "N":  Square.B_KNIGHT,
        "S":  Square.B_SILVER,
        "B":  Square.B_BISHOP,
        "R":  Square.B_ROOK,
        "G":  Square.B_GOLD,
        "K":  Square.B_KING,
        "+P": Square.B_PROMOTED_PAWN,
        "+L": Square.B_PROMOTED_LANCE,
        "+N": Square.B_PROMOTED_KNIGHT,
        "+S": Square.B_PROMOTED_SILVER,
        "+B": Square.B_PROMOTED_BISHOP,
        "+R": Square.B_PROMOTED_ROOK,
        "p":  Square.W_PAWN,
        "l":  Square.W_LANCE,
        "n":  Square.W_KNIGHT,
        "s":  Square.W_SILVER,
        "b":  Square.W_BISHOP,
        "r":  Square.W_ROOK,
        "g":  Square.W_GOLD,
        "k":  Square.W_KING,
        "+p": Square.W_PROMOTED_PAWN,
        "+l": Square.W_PROMOTED_LANCE,
        "+n": Square.W_PROMOTED_KNIGHT,
        "+s": Square.W_PROMOTED_SILVER,
        "+b": Square.W_PROMOTED_BISHOP,
        "+r": Square.W_PROMOTED_ROOK,
    ];

    immutable type_t[string] TO_TYPE = [
        "P":  Type.PAWN,
        "L":  Type.LANCE,
        "N":  Type.KNIGHT,
        "S":  Type.SILVER,
        "B":  Type.BISHOP,
        "R":  Type.ROOK,
        "G":  Type.GOLD,
        "p":  Type.PAWN,
        "l":  Type.LANCE,
        "n":  Type.KNIGHT,
        "s":  Type.SILVER,
        "b":  Type.BISHOP,
        "r":  Type.ROOK,
        "g":  Type.GOLD,
    ];

    Position p;
    p.squares = Square.WALL;

    string[] ss = sfen.strip().split(regex(r"\s+"));
    string boardState = ss[0];
    string sideToMove = ss[1];
    string piecesInHand = ss[2];
    string moveCount = ss[3];

    // 手番
    if (sideToMove != "b" && sideToMove != "w") {
        throw new StringException(sfen);
    }
    p.sideToMove = sideToMove == "b" ? Side.BLACK : Side.WHITE;

    // 盤面
    for (int i = 9; i >= 2; i--) {
        boardState = boardState.replace(to!string(i), "1".replicate(i)); // 2～9を1に開いておく
    }
    boardState = boardState.replace("/", "");
    auto m = boardState.matchAll(r"\+?.");
    for (int rank = 1; rank <= 9; rank++) {
        for (int file = 9; file >= 1; file--) {
            p.squares[file * 10 + rank] = TO_SQUARE[m.front.hit];
            m.popFront();
        }
    }

    // 持ち駒
    if (piecesInHand != "-") {
        // 例：S, 4P, b, 3n, p, 18P
        foreach (c; piecesInHand.matchAll(r"(\d*)(\D)")) {
            int num = (c[1] == "") ? 1 : to!int(c[1]);
            string piece = c[2];
            p.piecesInHand[piece[0].isUpper() ? Side.BLACK : Side.WHITE][TO_TYPE[piece]] += num;
        }
    }

    // ハッシュ値
    p.hash = 0;
    for (int i = 11; i <= 99; i++) {
        p.hash ^= HASH_SEED_BOARD[ p.squares[i] ][i];
    }
    for (side_t s = Side.BLACK; s <= Side.WHITE; s++) {
        for (type_t t = Type.PAWN; t <= Type.KING; t++) {
            p.hash ^= HASH_SEED_HAND[s][t][ p.piecesInHand[s][t] ];
        }
    }
    return p;
}
