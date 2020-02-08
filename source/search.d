import core.thread;
import eval;
import movegen;
import position;
import std.algorithm.comparison;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.datetime.stopwatch;
import std.random;
import std.stdio;
import text;
import types;
static import book, config, tt;


__gshared int REMAIN_SECONDS = config.TOTAL_SECONDS;


int ponder(const ref Position p, Move[] outPv)
{

    if (p.inMate()) {
        outPv[0] = Move.TORYO;
        outPv[1] = Move.NULL;
        return -15000;
    }

    {
        Move move = book.pick(p);
        if (move != Move.NULL) {
            outPv[0] = move;
            outPv[1] = Move.NULL;
            return 0;
        }
    }

    immutable int[] skipSize = [1, 2,2, 3,3,3,3, 4,4,4,4,4,4, 5,5,5,5,5,5,5,5,];
    SearchThread[] threads;
    for (int i = 0; i < config.SEARCH_THREADS; i++) {
        threads ~= new SearchThread(p, i, skipSize[i]);
    }
    foreach (ref t; threads) {
        t.start();
    }
    Thread.sleep(dur!("seconds")(min(config.SEARCH_SECONDS, REMAIN_SECONDS)));
    foreach (ref t; threads) {
        t.stop();
    }
    foreach (ref t; threads) {
        t.join();
    }

    int v = int.min;
    int d = int.min;
    stderr.writefln("");
    foreach (ref t; threads) {
        stderr.writefln("[%2d] %2d,%6d,%s", t.idx, t.completedDepth, t.bestValue, t.bestMoves.toString(p));
        if (v < t.bestValue && d <= t.completedDepth) {
            v = t.bestValue;
            d = t.completedDepth;
            outPv[0..64] = t.bestMoves[0..64];
        }
    }
    return v;
}


class SearchThread : Thread
{
    private int idx;
    private bool exit = false;
    private Position p;
    private int depthInit;
    private Move[64] bestMoves;
    private int bestValue = int.min;
    private int completedDepth;


    this(Position p, int idx, int depth)
    {
        this.p = p;
        this.idx = idx;
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
            this.search0(p, depth, this.bestMoves, this.bestValue);
        }
        return;
    }


    /**
     * ルート局面用のsearch
     * 読み筋をstderrに出力する
     * Params:
     *      p        = 局面
     *      depth    = 探索深さ(>=1)
     *      outPv    = 読み筋を出力する
     *      outScore = 評価値を出力する
     */
    private void search0(Position p, int depth, Move[] outPv, ref int outValue)
    {
        Move[64] pv;

        Move[593] moves;
        int length = p.legalMoves(moves);
        if (length == 0) {
            return;
        }
        randomShuffle(moves[0..length]);
        if (outPv[0] != Move.NULL) {
            swap(moves[0], moves[0..length].find(outPv[0])[0]);
        }

        int a = short.min;
        const int b = short.max;
        if (this.idx == 0) {
            stderr.writef("%d: ", depth);
        }
        foreach (Move move; moves[0..length]) {
            int value = -this.search(p.doMove(move), depth - 1, -b, -a, pv);
            if (this.exit) {
                return;
            }
            if (a < value) {
                a = value;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
                outValue = value;
                this.completedDepth = depth;
                if (this.idx == 0) {
                    stderr.writef("%s(%d) ", move.toString(p), value);
                }
            }
        }
        if (this.idx == 0) {
            stderr.writefln("-> %s", outPv.toString(p));
        }
        return;
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
        if (this.exit) {
            return b;
        }

        if (p.inUchifuzume) {
            return 15000; // 打ち歩詰めされていれば勝ち
        }

        if (depth <= 0) {
            return this.qsearch(p, depth + 4, a, b, outPv);
        }

        if (!p.inCheck && depth + 1 <= 3 && b <= p.staticValue - 300) {
            return b;
        }

        Move[64] pv;

        if (doNullMove /* && !p.inCheck */ ) {
            immutable R = 2;
            int value = -this.search(p.doMove(Move.NULL_MOVE), depth - R - 1, -b, -b + 1, pv, false);
            if (b <= value) {
                return b;
            }
        }

        {
            Move move =  tt.probe(p.key);
            if (move.isValid(p)) {
                int value = -this.search(p.doMove(move), depth - 1, -b, -a, pv);
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
            int value = -this.search(p.doMove(move), depth - 1, -b, -a, pv);
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
                int value = -this.qsearch(p.doMove(move), depth - 1, -b, -a, pv);
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
            int value = -this.qsearch(p.doMove(move), depth - 1, -b, -a, pv);
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


}

