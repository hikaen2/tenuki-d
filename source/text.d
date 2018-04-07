import types;
import position;
import eval;
import hash_seed;
import std.string;
import std.stdio;
import std.format;
import std.conv;
import std.array;
import std.container;
import std.regex;
import std.ascii;
import std.array;
import std.regex;

/**
 * 手をCSA形式の文字列にする
 */
string toString(move_t m, const ref Position p)
{
    if (m == Move.TORYO) {
        return "%TORYO";
    }

    //    歩,   香,   桂,   銀,  角,    飛,   金,   玉,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable string[] CSA = [
        "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY",
    ];
    int from = m.isDrop() ? 0 : m.from();
    int to = m.to();
    type_t t = m.isDrop() ? m.from() : m.isPromote() ? p.squares[m.from()].promote().type() : p.squares[m.from()].type();
    return format("%s%02d%02d%s", (p.sideToMove == Side.BLACK ? "+" : "-"), from, to, CSA[t]);
}


string toString(const ref Position p)
{
    return format("hash: 0x%016x\nstaticValue: %d\n%s\n", p.hash, (p.sideToMove == Side.BLACK ? p.staticValue() : -p.staticValue()), p.toKi2());
}

/**
 * 局面をSFEN形式の文字列にする
 */
string toSfen(const ref Position p)
{
    //   歩,  香,  桂,  銀,  角,  飛,  金,  王,   と, 成香, 成桂, 成銀,   馬,   龍,  空, 壁
    immutable string[] TO_SFEN = [
        "P", "L", "N", "S", "B", "R", "G", "K", "+P", "+L", "+N", "+S", "+B", "+R", "1", "",
        "p", "l", "n", "s", "b", "r", "g", "k", "+p", "+l", "+n", "+s", "+b", "+r",
    ];

    Array!string lines;
    for (int rank = 1; rank <= 9; rank++) {
        string line;
        for (int file = 9; file >= 1; file--) {
            line ~= TO_SFEN[p.squares[file * 10 + rank]];
        }
        lines.insert(line);
    }
    string board = lines[].join("/");
    for (int i = 9; i >= 2; i--) {
        board = board.replace("1".replicate(i), to!string(i)); // '1'をまとめる
    }

    string side = (p.sideToMove == Side.BLACK ? "b" : "w");

    // 飛車, 角, 金, 銀, 桂, 香, 歩
    string hand;
    foreach (type_t t; [Type.ROOK, Type.BISHOP, Type.GOLD, Type.SILVER, Type.KNIGHT, Type.LANCE, Type.PAWN]) {
        int n = p.piecesInHand[Side.BLACK][t];
        if (n > 0) {
            hand ~= (n > 1 ? to!string(n) : "") ~ TO_SFEN[t];
        }
    }
    foreach (type_t t; [Type.ROOK, Type.BISHOP, Type.GOLD, Type.SILVER, Type.KNIGHT, Type.LANCE, Type.PAWN]) {
        int n = p.piecesInHand[Side.WHITE][t];
        if (n > 0) {
            hand ~= (n > 1 ? to!string(n) : "") ~ TO_SFEN[t + 16];
        }
    }
    if (hand == "") {
        hand = "-";
    }

    return format("sfen %s %s %s %s", board, side, hand, p.moveCount);
}

/**
 * 局面をKI2形式の文字列にする
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
    for (side_t s = Side.BLACK; s <= Side.WHITE; s++) {
        for (type_t t = Type.PAWN; t <= Type.GOLD; t++) {
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
    for (int rank = 1; rank <= 9; rank++) {
        s ~= "|";
        for (int file = 9; file >= 1; file--) {
            s ~= BOARD[p.squares[file * 10 + rank]];
        }
        s ~= format("|%s\n", NUM[rank]);
    }
    s ~= "+---------------------------+\n";
    s ~= format("先手の持駒：%s\n", (hand[Side.BLACK] == "" ? "なし" : hand[Side.BLACK]));
    return s;
}
