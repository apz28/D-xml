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

private struct EnumBitFlagNegations(E)
if (isBitFlagEnum!(E))
{
nothrow @safe:
private:
    alias EType = OriginalType!E;

    EType _values;

public:
    @disable this();

    this(EType aValues)
    {
        _values = aValues;
    }

@property:
    EType values() const
    {
        return _values;
    }
}

struct EnumBitFlags(E)
if (isBitFlagEnum!(E))
{
nothrow @safe:
private:
    enum isBaseEnumType(T) = is(E == T);
    alias EType = OriginalType!E;

    EType _values;

public:
    this(E aValue)
    {
        _values = aValue;
    }

    this(T...)(T aValues)
    if (allSatisfy!(isBaseEnumType, T))
    {
        _values = 0;
        foreach (E e; aValues)
            _values |= e;
    }

    bool opCast(B: bool)() const
    {
        return _values != 0;
    }

    EType opCast(B)() const
    if (isImplicitlyConvertible!(EType, B))
    {
        return _values;
    }

    EnumBitFlagNegations opUnary(string op)() const
    if (op == "~")
    {
        return EnumBitFlagNegations(~_values);
    }

    auto ref opAssign(E aValue)
    {
        _values = aValue;
        return this;
    }

    auto ref opAssign(T...)(T aValues)
    if (allSatisfy!(isBaseEnumType, T))
    {
        _values = 0;
        foreach (E e; aValues)
            _values |= e;
        return this;
    }

    auto ref opOpAssign(string op)(E aValue)
    if (op == "^" || op == "|" || op == "&")
    {
        static if (op == "^")
            _values &= ~aValue;
        else static if (op == "|")
            _values |= aValue;
        else
            _values &= aValue;

        return this;
    }

    auto ref opOpAssign(string op)(EnumBitFlags aValues)
    if (op == "^" || op == "|" || op == "&")
    {
        static if (op == "^")
            _values &= ~aValues.values;
        else static if (op == "|")
            _values |= aValues.values;
        else
            _values &= aValues.values;

        return this;
    }

    auto ref opOpAssign(string op: "&")(EnumBitFlagNegations aValues)
    {
        _values &= aValues.values;

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

    auto opBinary(string op: "&")(EnumBitFlagNegations aValues) const
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

    pragma (inline, true)
    bool isOff(E aValue) const
    {
        assert(aValue != 0);

        return (_values & aValue) == 0;
    }

    pragma (inline, true)
    bool isOn(E aValue) const
    {
        assert(aValue != 0);

        return (_values & aValue) == aValue;
    }

    pragma (inline, true)
    bool isOnAny(E aValue) const
    {
        assert(aValue != 0);

        return (_values & aValue) != 0;
    }

@property:
    EType values()
    {
        return _values;
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
    V[size] _values;

public:
    this(T...)(T aValues)
    if (allSatisfy!(isEntryType, T))
    {
        foreach (ref Entry i; aValues)
            _values[i.e] = i.v;
    }
    
    V opIndex(E aEnum) const
    { 
        return _values[aEnum]; 
    }

    V opIndexAssign(V aValue, E aEnum)
    {
        return _values[aEnum] = aValue;
    }

    V opDispatch(string aEnumName)() const
    {
        import std.conv : to;

        immutable e = aEnumName.to!E;
        return this[e];
    }

    V opDispatch(string aEnumName)(V aValue)
    {
        import std.conv : to;

        immutable e = aEnumName.to!E;
        return this[e] = aValue;
    }

@property:
    size_t length() const
    {
        return size;
    }
}

unittest // EnumArray
{
    enum EnumTest
    {
        one,
        two,
        max
    }
    
    alias EnumTestTable = EnumArray!(EnumTest, int); 

    EnumTestTable testTable = EnumTestTable(
        EnumTestTable.Entry(EnumTest.one, 1),
        EnumTestTable.Entry(EnumTest.two, 2),
        EnumTestTable.Entry(EnumTest.max, int.max)
    );

    assert(testTable[EnumTest.one] == 1);
    assert(testTable[EnumTest.two] == 2);
    assert(testTable[EnumTest.max] == int.max);
}