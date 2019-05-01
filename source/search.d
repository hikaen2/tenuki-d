import types;
import text;
import position;
import movegen;
import eval;
import std.random;
import std.stdio;
import std.algorithm.comparison;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.datetime.stopwatch;
import core.thread;
static import book, config, tt;


private int COUNT = 0;
private StopWatch SW;
private int SECOND = config.SEARCH_SECONDS;
__gshared int REMAIN_SECONDS = config.TOTAL_SECONDS;


int ponder(const ref Position p, Move[] outPv)
{

    SECOND = min(config.SEARCH_SECONDS, REMAIN_SECONDS);

    Move m = Move.NULL;
    int value = 0;

    // for (int depth = 1; depth <= 6; depth++) {
    //     Position q = p;
    //     p.search0(depth, outPv, value);
    // }
    // writeln(COUNT);

    {
        Move move = book.pick(p);
        if (move != Move.NULL) {
            outPv[0] = move;
            outPv[1] = Move.NULL;
            return 0;
        }
    }

    Move[64][] pvs;
    Move[64] pv;
    SW = StopWatch(AutoStart.yes);

    immutable int[] skipSize = [1,1, 2,2,2,2, 3,3,3,3,3,3, 4,4,4,4,4,4,4,4,];
    HelperThread[] threads;
    for (int i = 1; i < config.SEARCH_THREADS; i++) {
        threads ~= new HelperThread(p, skipSize[i]);
    }
    foreach (ref t; threads) {
        t.start();
    }

    //for (int depth = 1; depth <= 6; depth++) {
    for (int depth = 1; SW.peek().total!"seconds" < SECOND; depth++) {
        p.search0(depth, pv, value);
        Move[64] v = pv;
        if (value <= -15000) {
            v[0] = Move.TORYO;
            v[1] = Move.NULL;
        }
        pvs ~= v;
    }
    //writeln(COUNT);

    foreach (ref t; threads) {
        t.stop();
    }
    foreach (ref t; threads) {
        t.join();
    }

    foreach_reverse (ref v; pvs[1..$]) {
        if (v[0] != Move.TORYO) {
            outPv[0..64] = v;
            return value;
        }
    }
    outPv[0] = Move.TORYO;
    outPv[1] = Move.NULL;
    return value;
}

/**
 * ルート局面用のsearch
 * 読み筋をstderrに出力する
 * Params:
 *      p        = 局面
 *      depth    = 探索深さ(>=1)
 *      outPv    = 読み筋を出力する
 *      outScore = 評価値を出力する
 * Returns: 評価値
 */
private int search0(Position p, int depth, Move[] outPv, ref int outScore)
{
    Move[64] pv;
    COUNT++;

    Move[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return 0;
    }
    randomShuffle(moves[0..length]);
    if (outPv[0] != Move.NULL) {
        swap(moves[0], moves[0..length].find(outPv[0])[0]);
    }

    int a = short.min;
    const int b = short.max;
    stderr.writef("%d: ", depth);
    foreach (Move move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (SW.peek().total!"seconds" >= SECOND) {
            break;
        }
        if (a < value) {
            a = value;
            // if (outPv[0] != move) {
            //     SW.reset();
            // }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
            stderr.writef("%s(%d) ", move.toString(p), value);
            outScore = value;
        }
    }
    stderr.writefln("\t-> %s", outPv.toString(p));

    return a;
}

/**
 * search
 * @param p
 * @param depth
 * @param a 探索済みminノードの最大値
 * @param b 探索済みmaxノードの最小値
 * @return 評価値
 */
private int search(Position p, int depth, int a, const int b, Move[] outPv, bool doNullMove = true)
{
    assert(a < b);

    outPv[0] = Move.NULL;
    if (SW.peek().total!"seconds" >= SECOND) {
        return 0;
    }

    if (p.inUchifuzume) {
        return 15000; // 打ち歩詰めされていれば勝ち
    }

    if (depth <= 0) {
        return p.qsearch(depth + 4, a, b, outPv);
    }
    COUNT++;

    if (!p.inCheck && depth + 1 <= 3 && b <= p.staticValue - 300) {
        return b;
    }

    Move[64] pv;

    if (doNullMove /* && !p.inCheck */ ) {
        immutable R = 2;
        int value = -p.doMove(Move.NULL_MOVE).search(depth - R - 1, -b, -b + 1, pv, false);
        if (b <= value) {
            return b;
        }
    }

    {
        Move move =  tt.probe(p.key);
        if (move.isValid(p)) {
            int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                if (b <= a) {
                    return b;
                }
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
    }

    Move[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return p.staticValue;
    }
    foreach (Move move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            tt.store(p.key, move);
            if (b <= a) {
                return b;
            }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
        }
    }
    return a;
}

/**
 * 静止探索
 */
private int qsearch(Position p, int depth, int a, const int b, Move[] outPv)
{
    assert(a < b);

    COUNT++;
    outPv[0] = Move.NULL;
    Move[64] pv;

    if (depth <= 0) {
        return p.staticValue;
    }

    a = max(a, p.staticValue);
    if (b <= a) {
        return b;
    }

    {
        Move move =  tt.probe(p.key);
        if (move.isValid(p) && p.board[move.to].isEnemyOf(p.sideToMove)) {
            int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                if (b <= a) {
                    return b;
                }
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
    }

    Move[128] moves;
    int length = p.capturelMoves(moves);
    foreach (Move move; moves[0..length]) {
        int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            tt.store(p.key, move);
            if (b <= a) {
                return b;
            }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
        }
    }
    return a;
}

/**
 * 局面pにおいて手番のある側が打ち歩詰めされているかどうかを返す
 */
private bool inUchifuzume(Position p)
{
    if (!p.previousMove.isDrop || p.previousMove.from != Type.PAWN || !p.inCheck) {
        return false; // 直前の指し手が打ち歩でない，または現局面が王手をかけられていない場合は，打ち歩詰めでない
    }

    Move[593] moves;
    int length = p.legalMoves(moves);
    foreach (Move move; moves[0..length]) {
        if (!p.doMove(move).doMove(Move.NULL_MOVE).inCheck) {
            return false; // 王手を解除する手があれば打ち歩詰めでない
        }
    }
    return true; // 王手を解除する手がなければ打ち歩詰め
}


class HelperThread : Thread
{
    private int idx;
    private bool exit = false;
    private Position p;
    private int depthInit;
    private Move bestMove = Move.NULL;

    this(Position p, int depth)
    {
        this.p = p;
        this.depthInit = depth;
        super(&run);
    }

    public void stop()
    {
        this.exit = true;
    }

    private void run()
    {
        for (int depth = this.depthInit; !this.exit; depth++) {
            this.search0(p, depth);
        }
    }

    private void search0(Position p, int depth)
    {
        Move[593] moves;
        int length = p.legalMoves(moves);
        if (length == 0) {
            return;
        }
        randomShuffle(moves[0..length]);

        int a = short.min;
        const int b = short.max;
        if (this.bestMove != Move.NULL) {
            int value = -this.search(p.doMove(this.bestMove), depth - 1, -b, -a);
            if (a < value) {
                a = value;
            }
        }
        foreach (Move move; moves[0..length]) {
            int value = -this.search(p.doMove(move), depth - 1, -b, -a);
            if (a < value) {
                a = value;
                this.bestMove = move;
            }
        }
    }

    private int search(Position p, int depth, int a, const int b, bool doNullMove = true)
    {
        assert(a < b);

        if (this.exit) {
            return b;
        }

        if (p.inUchifuzume) {
            return 15000; // 打ち歩詰めされていれば勝ち
        }

        if (depth <= 0) {
            return p.staticValue;
            //return p.qsearch(depth + 4, a, b, outPv);
        }

        if (!p.inCheck && depth + 1 <= 3 && b <= p.staticValue - 300) {
            return b;
        }

        if (doNullMove /* && !p.inCheck */ ) {
            immutable R = 2;
            int value = -this.search(p.doMove(Move.NULL_MOVE), depth - R - 1, -b, -b + 1, false);
            if (b <= value) {
                return b;
            }
        }

        {
            Move move =  tt.probe(p.key);
            if (move.isValid(p)) {
                int value = -this.search(p.doMove(move), depth - 1, -b, -a);
                if (a < value) {
                    a = value;
                    if (b <= a) {
                        return b;
                    }
                }
            }
        }

        Move[593] moves;
        int length = p.legalMoves(moves);
        if (length == 0) {
            return p.staticValue;
        }
        foreach (Move move; moves[0..length]) {
            int value = -this.search(p.doMove(move), depth - 1, -b, -a);
            if (a < value) {
                a = value;
                tt.store(p.key, move);
                if (b <= a) {
                    return b;
                }
            }
        }
        return a;
    }

}

