module search;

import core.sys.posix.pthread;
import core.sys.posix.unistd;
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


int ponder(const ref Position pos, Move[] outPv)
{

    if (pos.inMate()) {
        outPv[0] = Move.TORYO;
        outPv[1] = Move.NULL;
        return -15000;
    }

    {
        Move move = book.pick(pos);
        if (move != Move.NULL) {
            outPv[0] = move;
            outPv[1] = Move.NULL;
            return 0;
        }
    }

    foreach (ref e; threadContexts) e.pos = pos;
    foreach (ref e; threadContexts) pthread_cond_signal(&e.cond); // スレッドを起こす
    Thread.sleep(dur!("seconds")(min(config.SEARCH_SECONDS, REMAIN_SECONDS))); // 待つ
    foreach (ref e; threadContexts) e.stop_request = true;
    do { usleep(1000); } while(any!((e) => e.is_busy)(threadContexts[]));

    int v = int.min;
    int d = int.min;
    stderr.writefln("");
    foreach (ref t; threadContexts) {
        //stderr.writefln("[%2d] %2d,%6d,%s", t.id, t.completedDepth, t.bestValue, t.bestMoves.toString(pos));
        if (v < t.bestValue && d <= t.completedDepth) {
            v = t.bestValue;
            d = t.completedDepth;
            outPv[0..64] = t.bestMoves[0..64];
        }
    }
    return v;
}


__gshared ThreadContext[config.SEARCH_THREADS] threadContexts;

shared static this()
{
    foreach (int i, ref e; threadContexts) {
        e.id = i;
        pthread_mutex_init(&e.mutex, null);
        pthread_cond_init(&e.cond, null);
        pthread_create(&e.thread, null, &start_routine, cast(void*)&e);
    }
}

extern (C) void* start_routine(void* arg)
{
    ThreadContext* threadContext = cast(ThreadContext*)arg;
    pthread_mutex_lock(&threadContext.mutex);
    while (pthread_cond_wait(&threadContext.cond, &threadContext.mutex) == 0) {

        threadContext.is_busy = true;
        threadContext.run();
        threadContext.is_busy = false;

    }
    pthread_mutex_unlock(&threadContext.mutex);
    return null;
}

struct ThreadContext {
    int id;
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t cond;

    bool is_busy = false;
    Position pos;

    bool stop_request = false;
    Move[64] bestMoves;
    int bestValue = int.min;
    int completedDepth;

    private void run()
    {
        this.stop_request = false;
        this.bestMoves = Move.NULL;
        this.bestValue = int.min;
        for (int depth = 1; !this.stop_request; depth++) {
            this.search0(this.pos, depth, this.bestMoves, this.bestValue);
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
    private void search0(Position pos, int depth, Move[] outPv, ref int outValue)
    {
        Move[64] pv;

        Move[593] moves;
        int length = pos.legalMoves(moves);
        if (length == 0) return;

        randomShuffle(moves[0..length]);
        if (outPv[0] != Move.NULL) swap(moves[0], moves[0..length].find(outPv[0])[0]);

        int a = short.min;
        const int b = short.max;
        if (this.id == 0) stderr.writef("%d: ", depth);

        foreach (Move move; moves[0..length]) {
            int value = -this.search(pos.doMove(move), depth - 1, -b, -a, pv);
            if (this.stop_request) return;

            if (a < value) {
                a = value;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
                outValue = value;
                this.completedDepth = depth;
                if (this.id == 0) stderr.writef("%s(%d) ", move.toString(pos), value);
            }
        }
        if (this.id == 0) stderr.writefln("-> %s", outPv.toString(pos));
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
    private int search(Position pos, int depth, int a, const int b, Move[] outPv, bool doNullMove = true)
    {
        assert(a < b);

        outPv[0] = Move.NULL;
        if (this.stop_request) return b;

        if (pos.inUchifuzume) return 15000; // 打ち歩詰めされていれば勝ち

        if (depth <= 0) return this.qsearch(pos, depth + 4, a, b, outPv);

        if (!pos.inCheck && depth + 1 <= 3 && b <= pos.staticValue - 300) return b;

        Move[64] pv;

        if (doNullMove) {
            immutable R = 2;
            int value = -this.search(pos.doMove(Move.NULL_MOVE), depth - R - 1, -b, -b + 1, pv, false);
            if (b <= value) return b;
        }

        {
            Move move =  tt.probe(pos.key);
            if (move.isValid(pos)) {
                int value = -this.search(pos.doMove(move), depth - 1, -b, -a, pv);
                if (a < value) {
                    a = value;
                    if (b <= a) return b;
                    outPv[0] = move;
                    outPv[1..64] = pv[0..63];
                }
            }
        }

        Move[593] moves;
        int length = pos.legalMoves(moves);
        if (length == 0) return pos.staticValue;

        foreach (Move move; moves[0..length]) {
            int value = -this.search(pos.doMove(move), depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                tt.store(pos.key, move);
                if (b <= a) return b;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
        return a;
    }

    /**
     * 静止探索
     */
    private int qsearch(Position pos, int depth, int a, const int b, Move[] outPv)
    {
        assert(a < b);

        outPv[0] = Move.NULL;
        Move[64] pv;

        if (depth <= 0) return pos.staticValue;

        a = max(a, pos.staticValue);
        if (b <= a) return b;

        {
            Move move =  tt.probe(pos.key);
            if (move.isValid(pos) && pos.board[move.to].isEnemyOf(pos.sideToMove)) {
                int value = -this.qsearch(pos.doMove(move), depth - 1, -b, -a, pv);
                if (a < value) {
                    a = value;
                    if (b <= a) return b;
                    outPv[0] = move;
                    outPv[1..64] = pv[0..63];
                }
            }
        }

        Move[128] moves;
        int length = pos.capturelMoves(moves);
        foreach (Move move; moves[0..length]) {
            int value = -this.qsearch(pos.doMove(move), depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                tt.store(pos.key, move);
                if (b <= a) return b;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
        return a;
    }
}
