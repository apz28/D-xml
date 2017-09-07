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

struct EnumBitFlags(E)
if (isBitFlagEnum!(E))
{
nothrow @safe:
private:
    enum isBaseEnumType(T) = is(E == T);
    alias EType = OriginalType!E;

    EType _values;

public:
    static struct EnumBitFlagNegations
    {
    private:
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

public:
    this(E aValue)
    {
        _values = aValue;
    }

    this(const(E)[] aValues)
    {
        _values = 0;
        foreach (i; aValues)
            _values |= i;
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

    auto ref opOpAssign(string op)(EnumBitFlags!E aValues)
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
        BitFlags res = this;
        res.opOpAssign!op(aValue);

        return res;
    }

    auto opBinary(string op)(EnumBitFlags!E aValues) const
    if (op == "^" || op == "|" || op == "&")
    {
        BitFlags res = this;
        res.opOpAssign!op(aValues);

        return res;
    }

    auto opBinary(string op: "&")(EnumBitFlagNegations aValues) const
    {
        BitFlags res = this;
        res.opOpAssign!op(aValues);

        return res;
    }

    auto opBinaryRight(string op)(E aValue) const
    if (op == "^" || op == "|" || op == "&")
    {
        return opBinary!op(aValue);
    }

    auto ref exc(E aValue)
    {
        return opOpAssign!"^"(aValue);
    }

    auto ref inc(E aValue)
    {
        return opOpAssign!"|"(aValue);
    }

    pragma (inline, true)
    bool any(const(E)[] aValues) const
    {
        foreach (i; aValues)
        {
            if (on(i))
                return true;
        }
        return false;
    }

    pragma (inline, true)
    bool off(E aValue) const
    {
        return aValue != 0 && (_values & aValue) == 0;
    }

    pragma (inline, true)
    bool on(E aValue) const
    {
        return aValue != 0 && (_values & aValue) == aValue;
    }

    auto ref set(E aValue, bool aOp)
    {
        if (aOp)
            return opOpAssign!"|"(aValue);
        else
            return opOpAssign!"^"(aValue);
    }
    
@property:
    EType values() const
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

        enum e = aEnumName.to!E;
        return _values[e];
    }

    version (none)
    V opDispatch(string aEnumName)(V aValue)
    {
        import std.conv : to;

        enum e = aEnumName.to!E;
        return _values[e] = aValue;
    }

    E getEnum(V aValue, E aDefault = E.min)
    {
        foreach (i; EnumMembers!E)
        {
            if (_values[i] == aValue)
                return i;
        }

        return aDefault;
    }

@property:
    size_t length() const
    {
        return size;
    }
}

unittest // EnumBitFlags
{
    import pham.xml_util;

    outputXmlTraceProgress("unittest xml_enum.EnumBitFlags");

    enum EnumTest
    {
        //none,
        one = 1 << 0,
        two = 1 << 1,
        three = 1 << 2
    }
    
    alias EnumTestFlags = EnumBitFlags!EnumTest;

    EnumTestFlags testFlags;

    assert(testFlags.values == 0);
    foreach (i; EnumMembers!EnumTest)
    {
        assert(testFlags.off(i));
        assert(!testFlags.on(i));
    }

    assert(testFlags.inc(EnumTest.one).on(EnumTest.one));
    assert(testFlags.off(EnumTest.two));
    assert(testFlags.off(EnumTest.three));

    assert(testFlags.inc(EnumTest.two).on(EnumTest.two));
    assert(testFlags.on(EnumTest.one));
    assert(testFlags.off(EnumTest.three));

    assert(testFlags.inc(EnumTest.three).on(EnumTest.three));

    assert(testFlags.values != 0);
    foreach (i; EnumMembers!EnumTest)
    {
        assert(!testFlags.off(i));
        assert(testFlags.on(i));
    }

    assert(testFlags.exc(EnumTest.one).off(EnumTest.one));
    assert(testFlags.on(EnumTest.two));
    assert(testFlags.on(EnumTest.three));

    assert(testFlags.exc(EnumTest.two).off(EnumTest.two));
    assert(testFlags.off(EnumTest.two));
    assert(testFlags.on(EnumTest.three));

    assert(testFlags.exc(EnumTest.three).off(EnumTest.three));

    assert(testFlags.values == 0);
    foreach (i; EnumMembers!EnumTest)
    {
        assert(testFlags.off(i));
        assert(!testFlags.on(i));
    }
}

unittest // EnumArray
{
    import pham.xml_util;

    outputXmlTraceProgress("unittest xml_enum.EnumArray");

    enum EnumTest
    {
        one,
        two,
        max
    }
    
    alias EnumTestInt = EnumArray!(EnumTest, int); 

    EnumTestInt testInt = EnumTestInt(
        EnumTestInt.Entry(EnumTest.one, 1),
        EnumTestInt.Entry(EnumTest.two, 2),
        EnumTestInt.Entry(EnumTest.max, int.max)
    );

    assert(testInt.one == 1);
    assert(testInt.two == 2);
    assert(testInt.max == int.max);

    assert(testInt[EnumTest.one] == 1);
    assert(testInt[EnumTest.two] == 2);
    assert(testInt[EnumTest.max] == int.max);

    assert(testInt.getEnum(1) == EnumTest.one);
    assert(testInt.getEnum(2) == EnumTest.two);
    assert(testInt.getEnum(int.max) == EnumTest.max);
    assert(testInt.getEnum(3) == EnumTest.one); // Unknown -> return default min


    alias EnumTestString = EnumArray!(EnumTest, string); 

    EnumTestString testString = EnumTestString(
        EnumTestString.Entry(EnumTest.one, "1"),
        EnumTestString.Entry(EnumTest.two, "2"),
        EnumTestString.Entry(EnumTest.max, "int.max")
    );

    assert(testString[EnumTest.one] == "1");
    assert(testString[EnumTest.two] == "2");
    assert(testString[EnumTest.max] == "int.max");

    assert(testString.getEnum("1") == EnumTest.one);
    assert(testString.getEnum("2") == EnumTest.two);
    assert(testString.getEnum("int.max") == EnumTest.max);
    assert(testString.getEnum("3") == EnumTest.one); // Unknown -> return default min
}
