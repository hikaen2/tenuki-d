
alias side_t = ubyte;
alias type_t = ubyte;
alias dir_t = byte;
alias square_t = ubyte;
alias move_t = ushort;

struct Side {
    enum BLACK             = 0;  // 先手
    enum WHITE             = 1;  // 後手
};

struct Type {
    enum PAWN              = 0;  // 歩
    enum LANCE             = 1;  // 香
    enum KNIGHT            = 2;  // 桂
    enum SILVER            = 3;  // 銀
    enum BISHOP            = 4;  // 角
    enum ROOK              = 5;  // 飛
    enum GOLD              = 6;  // 金
    enum KING              = 7;  // 王
    enum PROMOTED_PAWN     = 8;  // と
    enum PROMOTED_LANCE    = 9;  // 成香
    enum PROMOTED_KNIGHT   = 10; // 成桂
    enum PROMOTED_SILVER   = 11; // 成銀
    enum PROMOTED_BISHOP   = 12; // 馬
    enum PROMOTED_ROOK     = 13; // 龍
    enum EMPTY             = 14; // 空
    enum WALL              = 15; // 壁
};

/**
 * 升
 * xxx1xxxx side
 * xxxx1111 type
 */
struct Square {
    enum W                 = 0b00010000;
    enum B_PAWN            = 0;
    enum B_LANCE           = 1;
    enum B_KNIGHT          = 2;
    enum B_SILVER          = 3;
    enum B_BISHOP          = 4;
    enum B_ROOK            = 5;
    enum B_GOLD            = 6;
    enum B_KING            = 7;
    enum B_PROMOTED_PAWN   = 8;
    enum B_PROMOTED_LANCE  = 9;
    enum B_PROMOTED_KNIGHT = 10;
    enum B_PROMOTED_SILVER = 11;
    enum B_PROMOTED_BISHOP = 12;
    enum B_PROMOTED_ROOK   = 13;
    enum EMPTY             = 14;
    enum WALL              = 15;
    enum W_PAWN            = 16;
    enum W_LANCE           = 17;
    enum W_KNIGHT          = 18;
    enum W_SILVER          = 19;
    enum W_BISHOP          = 20;
    enum W_ROOK            = 21;
    enum W_GOLD            = 22;
    enum W_KING            = 23;
    enum W_PROMOTED_PAWN   = 24;
    enum W_PROMOTED_LANCE  = 25;
    enum W_PROMOTED_KNIGHT = 26;
    enum W_PROMOTED_SILVER = 27;
    enum W_PROMOTED_BISHOP = 28;
    enum W_PROMOTED_ROOK   = 29;

    static bool isBlack(square_t sq) {
        return sq <= Square.B_PROMOTED_ROOK;
    }

    static bool isWhite(square_t sq) {
        return sq >= Square.W_PAWN;
    }

    static bool isFriend(square_t sq, side_t s) {
        return s == Side.BLACK ? isBlack(sq) : isWhite(sq);
    }

    static bool isEnemy(square_t sq, side_t s) {
        return s == Side.BLACK ? isWhite(sq) : isBlack(sq);
    }

    static type_t typeOf(square_t sq) {
        return sq & 0b00001111;
    }

    static square_t promote(square_t sq) {
        return sq | 0b00001000;
    }

    static square_t unpromote(square_t sq) {
        return sq & 0b11110111;
    }
};

/**
 * 手
 * 1xxxxxxx xxxxxxxx promote
 * x1xxxxxx xxxxxxxx drop
 * xx111111 1xxxxxxx from
 * xxxxxxxx x1111111 to
 */
struct Move {
    static move_t create(int from, int to) {
        return cast(move_t)(from << 7 | to);
    }

    static move_t createPromote(int from, int to) {
        return cast(move_t)(from << 7 | to | 0b1000000000000000);
    }

    static move_t createDrop(type_t t, int to) {
        return cast(move_t)(t << 7 | to | 0b0100000000000000);
    }

    static ubyte from(move_t m) {
        return cast(ubyte)((m >> 7) & 0b01111111);
    }

    static ubyte to(move_t m) {
        return cast(ubyte)(m & 0b01111111);
    }

    static bool isPromote(move_t m) {
        return (m & 0b1000000000000000) != 0;
    }

    static bool isDrop(move_t m) {
        return (m & 0b0100000000000000) != 0;
    }
};

/**
 * Direction
 * 1111111x value
 * xxxxxxx1 fly
 */
struct Dir
{
    enum N =  -1 * 2; //  -1 << 1
    enum E = -10 * 2; // -10 << 1
    enum W = +10 * 2; // +10 << 1
    enum S =  +1 * 2; //  +1 << 1
    enum NE = N + E;
    enum NW = N + W;
    enum SE = S + E;
    enum SW = S + W;
    enum NNE = N + N + E;
    enum NNW = N + N + W;
    enum FN = N | 1;
    enum FE = E | 1;
    enum FW = W | 1;
    enum FS = S | 1;
    enum FNE = NE | 1;
    enum FNW = NW | 1;
    enum FSE = SE | 1;
    enum FSW = SW | 1;

    static bool isFly(dir_t d) {
        return (d & 1) != 0;
    }

    static int value(dir_t d) {
        return d >> 1;
    }
};

/**
 * 局面
 */
struct Position
{
    square_t[111] squares;
    ubyte[8][2] piecesInHand;
    bool sideToMove;
};
