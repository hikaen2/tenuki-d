
alias side_t = ubyte;
alias type_t = ubyte;
alias dir_t = byte;
alias square_t = ubyte;
alias move_t = ushort;

/**
 * 局面
 */
struct Position
{
    square_t[111] squares;
    ubyte[8][2] piecesInHand;
    bool sideToMove;
    ulong hash;
}

enum Side : side_t
{
    BLACK             = 0,  // 先手
    WHITE             = 1,  // 後手
}

enum Type : type_t
{
    PAWN              = 0,  // 歩
    LANCE             = 1,  // 香
    KNIGHT            = 2,  // 桂
    SILVER            = 3,  // 銀
    BISHOP            = 4,  // 角
    ROOK              = 5,  // 飛
    GOLD              = 6,  // 金
    KING              = 7,  // 王
    PROMOTED_PAWN     = 8,  // と
    PROMOTED_LANCE    = 9,  // 成香
    PROMOTED_KNIGHT   = 10, // 成桂
    PROMOTED_SILVER   = 11, // 成銀
    PROMOTED_BISHOP   = 12, // 馬
    PROMOTED_ROOK     = 13, // 龍
    EMPTY             = 14, // 空
    WALL              = 15, // 壁
}

/**
 * 升
 * xxx1xxxx side
 * xxxx1111 type
 */
enum Square : square_t
{
    W                 = 0b00010000,
    B_PAWN            = 0,
    B_LANCE           = 1,
    B_KNIGHT          = 2,
    B_SILVER          = 3,
    B_BISHOP          = 4,
    B_ROOK            = 5,
    B_GOLD            = 6,
    B_KING            = 7,
    B_PROMOTED_PAWN   = 8,
    B_PROMOTED_LANCE  = 9,
    B_PROMOTED_KNIGHT = 10,
    B_PROMOTED_SILVER = 11,
    B_PROMOTED_BISHOP = 12,
    B_PROMOTED_ROOK   = 13,
    EMPTY             = 14,
    WALL              = 15,
    W_PAWN            = 16,
    W_LANCE           = 17,
    W_KNIGHT          = 18,
    W_SILVER          = 19,
    W_BISHOP          = 20,
    W_ROOK            = 21,
    W_GOLD            = 22,
    W_KING            = 23,
    W_PROMOTED_PAWN   = 24,
    W_PROMOTED_LANCE  = 25,
    W_PROMOTED_KNIGHT = 26,
    W_PROMOTED_SILVER = 27,
    W_PROMOTED_BISHOP = 28,
    W_PROMOTED_ROOK   = 29,
}

/**
 * Direction
 * 1111111x value
 * xxxxxxx1 fly
 */
enum Dir : dir_t
{
    N =  -1 * 2, //  -1 << 1
    E = -10 * 2, // -10 << 1
    W = +10 * 2, // +10 << 1
    S =  +1 * 2, //  +1 << 1
    NE = N + E,
    NW = N + W,
    SE = S + E,
    SW = S + W,
    NNE = N + N + E,
    NNW = N + N + W,
    FN = N | 1,
    FE = E | 1,
    FW = W | 1,
    FS = S | 1,
    FNE = NE | 1,
    FNW = NW | 1,
    FSE = SE | 1,
    FSW = SW | 1,
}

/**
 * 手
 * 1xxxxxxx xxxxxxxx promote
 * x1xxxxxx xxxxxxxx drop
 * xx111111 1xxxxxxx from
 * xxxxxxxx x1111111 to
 */
enum Move : move_t
{
    TORYO = 0,
}

// square_tを引数にとる関数
bool isBlack(square_t sq) { return sq <= Square.B_PROMOTED_ROOK; }
bool isWhite(square_t sq) { return sq >= Square.W_PAWN; }
bool isFriend(square_t sq, side_t s) { return s == Side.BLACK ? sq.isBlack() : sq.isWhite(); }
bool isEnemy(square_t sq, side_t s) { return s == Side.BLACK ? sq.isWhite() : sq.isBlack(); }
type_t type(square_t sq) { return sq & 0b00001111; }
square_t promote(square_t sq) { return sq | 0b00001000; }
square_t unpromote(square_t sq) { return sq & 0b11110111; }

// move_tを返す関数
move_t createMove(int from, int to) { return cast(move_t)(from << 7 | to); }
move_t createPromote(int from, int to) { return cast(move_t)(from << 7 | to | 0b1000000000000000); }
move_t createDrop(type_t t, int to) { return cast(move_t)(t << 7 | to | 0b0100000000000000); }

// move_tを引数にとる関数
ubyte from(move_t m) { return cast(ubyte)((m >> 7) & 0b01111111); }
ubyte to(move_t m) { return cast(ubyte)(m & 0b01111111); }
bool isPromote(move_t m) { return (m & 0b1000000000000000) != 0; }
bool isDrop(move_t m) { return (m & 0b0100000000000000) != 0; }

// dir_tを引数にとる関数
bool isFly(dir_t d) { return (d & 1) != 0; }
int value(dir_t d) { return d >> 1; }
