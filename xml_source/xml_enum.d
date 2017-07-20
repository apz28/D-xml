/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml_enum;

import std.meta : allSatisfy;
import std.traits : EnumMembers, OriginalType;
import std.typecons : isBitFlagEnum; 

private struct BitFlagNegations(E)
if (isBitFlagEnum!(E))
{
nothrow @safe:
private:
    alias EType = OriginalType!E;

    EType values;

public:
    @disable this();

    this(EType aValues)
    {
        values = aValues;
    }
}

struct EnumBitFlags(E)
if (isBitFlagEnum!(E))
{
nothrow @safe:
private:
    enum isBaseEnumType(T) = is(E == T);
    alias EType = OriginalType!E;

    EType values;

public:
    this(E aValue)
    {
        values = aValue;
    }

    this(T...)(T aValues)
    if (allSatisfy!(isBaseEnumType, T))
    {
        values = 0;
        foreach (E e; aValues)
            values |= e;
    }

    bool opCast(B: bool)() const
    {
        return values != 0;
    }

    EType opCast(B)() const
    if (isImplicitlyConvertible!(EType, B))
    {
        return values;
    }

    BitFlagNegations opUnary(string op)() const
    if (op == "~")
    {
        return BitFlagNegations(~values);
    }

    auto ref opAssign(E aValue)
    {
        values = aValue;
        return this;
    }

    auto ref opAssign(T...)(T aValues)
    if (allSatisfy!(isBaseEnumType, T))
    {
        values = 0;
        foreach (E e; aValues)
            values |= e;
        return this;
    }

    auto ref opOpAssign(string op)(E aValue)
    if (op == "^" || op == "|" || op == "&")
    {
        static if (op == "^")
            values &= ~aValue;
        else static if (op == "|")
            values |= aValue;
        else
            values &= aValue;

        return this;
    }

    auto ref opOpAssign(string op)(EnumBitFlags aValues)
    if (op == "^" || op == "|" || op == "&")
    {
        static if (op == "^")
            values &= ~aValues.values;
        else static if (op == "|")
            values |= aValues.values;
        else
            values &= aValues.values;

        return this;
    }

    auto ref opOpAssign(string op: "&")(BitFlagNegations aValues)
    {
        values &= aValues.values;

        return this;
    }

    auto opBinary(string op)(E aValue) const
    if (op == "^" || op == "|" || op == "&")
    {
        BitFlags result = this;
        result.opOpAssign!op(aValue);

        return result;
    }

    auto opBinary(string op)(EnumBitFlags aValues) const
    if (op == "^" || op == "|" || op == "&")
    {
        BitFlags result = this;
        result.opOpAssign!op(aValues);

        return result;
    }

    auto opBinary(string op: "&")(BitFlagNegations aValues) const
    {
        BitFlags result = this;
        result.opOpAssign!op(aValues);

        return result;
    }

    auto opBinaryRight(string op)(E aValue) const
    if (op == "^" || op == "|" || op == "&")
    {
        return opBinary!op(aValue);
    }

    auto ref exclude(E aValue)
    {
        return opOpAssign!"^"(aValue);
    }

    auto ref include(E aValue)
    {
        return opOpAssign!"|"(aValue);
    }

    pragma(inline, true)
    bool isOff(E aValue) const
    {
        assert(aValue != 0);

        return ((values & aValue) == 0);
    }

    pragma(inline, true)
    bool isOn(E aValue) const
    {
        assert(aValue != 0);

        return ((values & aValue) == aValue);
    }

    pragma(inline, true)
    bool isOnAny(E aValue) const
    {
        assert(aValue != 0);

        return ((values & aValue) != 0);
    }
}

struct EnumArray(E, V) 
{
nothrow @safe:
public:
    struct Entry 
    {
        E e;
        V v;
    }

private:
    enum isEntryType(T) = is(Entry == T);
    enum size = EnumMembers!E.length;
    V[size] values;

public:
    this(T...)(T aValues)
    if (allSatisfy!(isEntryType, T))
    {
        foreach (ref Entry i; aValues)
            values[i.e] = i.v;
    }
    
    V opIndex(E aEnum) const
    { 
        return values[aEnum]; 
    }

    V opIndexAssign(V aValue, E aEnum)
    {
        return values[aEnum] = aValue;
    }

    V opDispatch(string aEnumName)() const
    {
        import std.conv : to;

        return this[aEnumName.to!E];
    }

    V opDispatch(string aEnumName)(V aValue)
    {
        import std.conv : to;

        return this[aEnumName.to!E] = aValue;
    }
}
