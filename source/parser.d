import types;
import std.array;
import std.ascii;
import std.conv;
import std.regex;
import std.string;
static import zobrist;

Move parseMove(string s, const ref Position p)
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

    immutable int[] ADDRESS = [
         -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
         -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,
         -1,  9, 10, 11, 12, 13, 14, 15, 16, 17,
         -1, 18, 19, 20, 21, 22, 23, 24, 25, 26,
         -1, 27, 28, 29, 30, 31, 32, 33, 34, 35,
         -1, 36, 37, 38, 39, 40, 41, 42, 43, 44,
         -1, 45, 46, 47, 48, 49, 50, 51, 52, 53,
         -1, 54, 55, 56, 57, 58, 59, 60, 61, 62,
         -1, 63, 64, 65, 66, 67, 68, 69, 70, 71,
         -1, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    ];

    auto m = s.matchFirst(r"(-|\+)(\d{2})(\d{2})(\w{2})");
    int from = ADDRESS[to!int(m[2])];
    int to = ADDRESS[to!int(m[3])];
    type_t t = DIC[m[4]];

    if (from == -1) {
        return createDrop(t, to); // fromが0なら駒打ち
    } else if (t != p.board[from].type()) {
        return createPromote(from, to); // 成る
    } else {
        return createMove(from, to);
    }
}

Position parsePosition(string sfen)
{
    immutable Square[string] TO_SQUARE = [
        "1":  Square.EMPTY,
        "P":  Square.B_PAWN,
        "L":  Square.B_LANCE,
        "N":  Square.B_KNIGHT,
        "S":  Square.B_SILVER,
        "G":  Square.B_GOLD,
        "B":  Square.B_BISHOP,
        "R":  Square.B_ROOK,
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
        "g":  Square.W_GOLD,
        "b":  Square.W_BISHOP,
        "r":  Square.W_ROOK,
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
        "G":  Type.GOLD,
        "B":  Type.BISHOP,
        "R":  Type.ROOK,
        "p":  Type.PAWN,
        "l":  Type.LANCE,
        "n":  Type.KNIGHT,
        "s":  Type.SILVER,
        "g":  Type.GOLD,
        "b":  Type.BISHOP,
        "r":  Type.ROOK,
    ];

    Position p;
    p.board = Square.EMPTY;

    string[] ss = sfen.strip().split(regex(r"\s+"));
    if (ss[0] != "sfen") {
        throw new StringException(sfen);
    }
    string boardState = ss[1];
    string sideToMove = ss[2];
    string piecesInHand = ss[3];
    string moveCount = ss[4];

    p.moveCount = to!short(moveCount);

    // 手番
    if (sideToMove != "b" && sideToMove != "w") {
        throw new StringException(sfen);
    }
    p.sideToMove = sideToMove == "b" ? Color.BLACK : Color.WHITE;

    // 盤面
    for (int i = 9; i >= 2; i--) {
        boardState = boardState.replace(to!string(i), "1".replicate(i)); // 2～9を1に開いておく
    }
    boardState = boardState.replace("/", "");
    auto m = boardState.matchAll(r"\+?.");
    for (int rank = 0; rank <= 8; rank++) {
        for (int file = 8; file >= 0; file--) {
            p.board[file * 9 + rank] = TO_SQUARE[m.front.hit];
            m.popFront();
        }
    }

    // 持ち駒
    if (piecesInHand != "-") {
        // 例：S, 4P, b, 3n, p, 18P
        foreach (c; piecesInHand.matchAll(r"(\d*)(\D)")) {
            int num = (c[1] == "") ? 1 : to!int(c[1]);
            string piece = c[2];
            p.piecesInHand[piece[0].isUpper() ? Color.BLACK : Color.WHITE][TO_TYPE[piece]] += num;
        }
    }

    // ハッシュ値
    p.key = 0;
    for (int i = SQ11; i <= SQ99; i++) {
        p.key ^= zobrist.PSQ[ p.board[i].i ][i];
    }
    for (color_t s = Color.BLACK; s <= Color.WHITE; s++) {
        for (type_t t = Type.PAWN; t <= Type.KING; t++) {
            p.key ^= zobrist.HAND[s][t][ p.piecesInHand[s][t] ];
        }
    }
    return p;
}
