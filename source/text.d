import types;
import eval;
import std.array;
import std.conv;
import std.format;
import std.stdio;

/**
 * mのCSA形式の文字列を返す
 */
string toString(Move m, const ref Position p)
{
    if (m == Move.TORYO) {
        return "%TORYO";
    }

    immutable ubyte[] NUM = [
        11, 12, 13, 14, 15, 16, 17, 18, 19,
        21, 22, 23, 24, 25, 26, 27, 28, 29,
        31, 32, 33, 34, 35, 36, 37, 38, 39,
        41, 42, 43, 44, 45, 46, 47, 48, 49,
        51, 52, 53, 54, 55, 56, 57, 58, 59,
        61, 62, 63, 64, 65, 66, 67, 68, 69,
        71, 72, 73, 74, 75, 76, 77, 78, 79,
        81, 82, 83, 84, 85, 86, 87, 88, 89,
        91, 92, 93, 94, 95, 96, 97, 98, 99,
    ];

    //    歩,   香,   桂,   銀,  角,    飛,   金,   玉,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable string[] CSA = [
        "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY",
    ];
    int from = m.isDrop ? 0 : NUM[m.from];
    int to = NUM[m.to];
    type_t t = m.isDrop ? m.from : m.isPromote ? p.squares[m.from].promote.type : p.squares[m.from].type;
    return format("%s%02d%02d%s", (p.sideToMove == Side.BLACK ? "+" : "-"), from, to, CSA[t]);
}

string toString(const ref Position p)
{
    return format("%s\nhash: 0x%016x\nstaticValue: %d\n%s\n", p.toSfen, p.hash, (p.sideToMove == Side.BLACK ? p.staticValue : -p.staticValue), p.toKi2());
}

/**
 * pのSFEN形式の文字列を返す
 */
string toSfen(const ref Position p)
{
    //   歩,  香,  桂,  銀,  角,  飛,  金,  王,   と, 成香, 成桂, 成銀,   馬,   龍,  空, 壁
    immutable string[] TO_SFEN = [
        "P", "L", "N", "S", "B", "R", "G", "K", "+P", "+L", "+N", "+S", "+B", "+R", "1", "",
        "p", "l", "n", "s", "b", "r", "g", "k", "+p", "+l", "+n", "+s", "+b", "+r",
    ];

    string[] lines;
    for (int rank = 0; rank <= 8; rank++) {
        string line;
        for (int file = 8; file >= 0; file--) {
            line ~= TO_SFEN[p.squares[file * 9 + rank]];
        }
        lines ~= line;
    }
    string board = lines.join("/");
    for (int i = 9; i >= 2; i--) {
        board = board.replace("1".replicate(i), to!string(i)); // '1'をまとめる
    }

    string side = (p.sideToMove == Side.BLACK ? "b" : "w");

    // 飛車, 角, 金, 銀, 桂, 香, 歩
    string hand;
    foreach (side_t s; [Side.BLACK, Side.WHITE]) {
        foreach (type_t t; [Type.ROOK, Type.BISHOP, Type.GOLD, Type.SILVER, Type.KNIGHT, Type.LANCE, Type.PAWN]) {
            int n = p.piecesInHand[s][t];
            if (n > 0) {
                hand ~= (n > 1 ? to!string(n) : "") ~ TO_SFEN[t | s << 4];
            }
        }
    }
    if (hand == "") {
        hand = "-";
    }

    return format("sfen %s %s %s %s", board, side, hand, p.moveCount);
}

/**
 * pのKI2形式の文字列を返す
 */
string toKi2(const ref Position p)
{
    immutable string[] BOARD = [
        " 歩", " 香", " 桂", " 銀", " 角", " 飛", " 金", " 玉", " と", " 杏", " 圭", " 全", " 馬", " 龍", " ・", " 壁",
        "v歩", "v香", "v桂", "v銀", "v角", "v飛", "v金", "v玉", "vと", "v杏", "v圭", "v全", "v馬", "v龍",
    ];

    immutable string[] HAND = [
        "歩", "香", "桂", "銀", "角", "飛", "金",
    ];

    immutable string[] NUM = [
        "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八",
    ];

    string[2] hand;
    foreach (side_t s; [Side.BLACK, Side.WHITE]) {
        foreach (type_t t; [Type.ROOK, Type.BISHOP, Type.GOLD, Type.SILVER, Type.KNIGHT, Type.LANCE, Type.PAWN]) {
            int n = p.piecesInHand[s][t];
            if (n > 0) {
                hand[s] ~= format("%s%s　", HAND[t], (n > 1 ? NUM[n] : ""));
            }
        }
    }

    string s;
    s ~= format("後手の持駒：%s\n", (hand[Side.WHITE] == "" ? "なし" : hand[Side.WHITE]));
    s ~= "  ９ ８ ７ ６ ５ ４ ３ ２ １\n";
    s ~= "+---------------------------+\n";
    for (int rank = 0; rank <= 8; rank++) {
        s ~= "|";
        for (int file = 8; file >= 0; file--) {
            s ~= BOARD[p.squares[file * 9 + rank]];
        }
        s ~= format("|%s\n", NUM[rank + 1]);
    }
    s ~= "+---------------------------+\n";
    s ~= format("先手の持駒：%s\n", (hand[Side.BLACK] == "" ? "なし" : hand[Side.BLACK]));
    return s;
}
