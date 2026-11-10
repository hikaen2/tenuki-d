module search;

import core.sys.posix.pthread;
import core.sys.posix.unistd;
import core.stdc.stdlib : calloc;
import core.thread;
import eval;
import movegen;
import position;
import std.algorithm.comparison;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.datetime.stopwatch;
import std.format;
import std.random;
import std.stdio;
import text;
import types;
import tt;
static import book;


// 1手の探索時間（ミリ秒）。最善手が変わったら、そこからこの時間だけ延長する
__gshared long SearchMillis = 0;

// 残り持ち時間（ミリ秒）。延長してもこれを超えない
__gshared long RemainingMillis = 0;

// この時間から探索を始めた（ミリ秒）
__gshared long startTime;

// この時間まで探索する（ミリ秒）
__gshared long endTime;


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

    startTime = getMonotonicTimeMillis();
    endTime = startTime + min(SearchMillis, RemainingMillis); // この時間まで探索する（ミリ秒）
    foreach (ref e; threadContexts) e.pos = pos;
    foreach (ref e; threadContexts) e.running = true; // 探索を開始する
    while(any!((e) => e.running)(threadContexts[])) Thread.sleep(1.msecs); // すべてのスレッドの探索が終了するまで待つ

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


/// 探索スレッドの状態。search_init で1回だけ確保し、長さを変えない（要素のアドレスを各スレッドに渡しているため）
/// GC ヒープではなく calloc で確保し、解放しない。探索スレッドは druntime の管理外で動き続けるので、
/// GC ヒープに置くとプロセス終了時の GC の後始末で解放され、スレッドが解放後のメモリを読んで落ちる。
__gshared ThreadContext[] threadContexts;

/**
 * 探索スレッドを生成する（1回だけ呼ぶ）
 */
void search_init(int threads)
{
    if (threads < 1) {
        throw new Exception(format("threads must be positive: %d", threads));
    }
    if (threadContexts.length != 0) {
        throw new Exception("search_init called twice");
    }
    auto p = cast(ThreadContext*) calloc(threads, ThreadContext.sizeof);
    if (p is null) {
        throw new Exception(format("calloc failed for %d search threads", threads));
    }
    threadContexts = p[0 .. threads];
    foreach (ref e; threadContexts) e = ThreadContext.init;
    foreach (i, ref e; threadContexts) {
        e.id = cast(int) i;
        const rc = pthread_create(&e.thread, null, &start_routine, cast(void*)&e);
        if (rc != 0) {
            throw new Exception(format("pthread_create failed for search thread %d: error %d", i, rc));
        }
    }
}

extern (C) void* start_routine(void* arg)
{
    ThreadContext* threadContext = cast(ThreadContext*)arg;
    while(true) {
        while (!threadContext.running) Thread.sleep(1.msecs); // runningがtureにされるまで待つ
        threadContext.run();
        threadContext.running = false;
    }
}

struct ThreadContext {
    int id;
    pthread_t thread;
    bool running = false;
    Position pos;

    Move[64] bestMoves;
    int bestValue = int.min;
    int completedDepth;
    Move previous = Move.NULL;

    private void run()
    {
        this.bestMoves = Move.NULL;
        this.bestValue = int.min;

        // 反復深化
        for (int depth = 1; getMonotonicTimeMillis() < endTime; depth++) {
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
        if (this.id == 0) {
            stderr.writef("%d: ", depth);
        }

        foreach (Move move; moves[0..length]) {
            int value = -this.search(pos.doMove(move), depth - 1, -b, -a, pv);
            if (getMonotonicTimeMillis() >= endTime) return;

            if (a < value) {
                a = value;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
                outValue = value;
                this.completedDepth = depth;
                if (this.id == 0) {
                    stderr.writef("%s(%d) ", move.toString(pos), value);
                    if (previous != move) { // 前回と違う手が見つかったら探索延長する
                        previous = move;
                        endTime = getMonotonicTimeMillis() + min(SearchMillis, RemainingMillis - (getMonotonicTimeMillis() - startTime)); // この時間まで探索する（ミリ秒）を延長する
                    }
                }
            }
        }
        if (this.id == 0) {
            stderr.writefln("-> %s", outPv.toString(pos));
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
    private int search(Position pos, int depth, int a, const int b, Move[] outPv, bool doNullMove = true)
    {
        assert(a < b);

        outPv[0] = Move.NULL;
        if (getMonotonicTimeMillis() >= endTime) return b;

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
            Move move =  tt_probe(pos.key);
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
                tt_store(pos.key, move);
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
            Move move =  tt_probe(pos.key);
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
                tt_store(pos.key, move);
                if (b <= a) return b;
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
        return a;
    }
}

/**
 * OSが起動してからのミリ秒を取る
 */
long getMonotonicTimeMillis()
{
    import core.sys.linux.time; // Linux専用
    timespec ts;
    //clock_gettime(CLOCK_MONOTONIC, &ts);
    clock_gettime(CLOCK_MONOTONIC_COARSE, &ts);
    assert(ts.tv_nsec / 1000000 < 1000);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
