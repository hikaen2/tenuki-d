module tt;

import core.atomic;
import core.sys.posix.sys.mman;
import std.format;
import std.stdint;
import std.stdio;
import types;
import config;

__gshared private TTEntry[] TT;

shared static this()
{
    immutable size_t n = Config.TT_SIZE + 1;
    immutable size_t bytes = n * TTEntry.sizeof;
    // MAP_POPULATE でカーネルが mmap 時点で全ページをプリフォルト → 物理RAM を即時確保
    void* p = mmap(null, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    assert(p != MAP_FAILED, "mmap failed for TT");
    TT = (cast(TTEntry*) p)[0 .. n];
}

struct TTEntry
{
    uint64_t key;
    uint16_t move16;
}

Move tt_probe(uint64_t key)
{
    TTEntry e = TT[key & Config.TT_SIZE];
    if (e.key == key)
    {
        return cast(Move)(e.move16);
    }
    return cast(Move)(0);
}

void tt_store(uint64_t key, Move m)
{
    const long address = (key & Config.TT_SIZE);
    if (TT[address].key == 0 || TT[address].key == key)
    {
        TT[address] = TTEntry(key, m.i);
        return;
    }
}

/**
 * 例："TT: 33,554,432 entries, 268,435,456 bytes"
 */
string tt_info()
{
    return format("TT: %,d entries, %,d bytes", TT.length, TT.length * TTEntry.sizeof);
}
