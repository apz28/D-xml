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

module pham.utl_enumset;

import std.meta : allSatisfy;
import std.traits : EnumMembers, isIntegral;

private
size_t maxBits() pure nothrow
{
    return ulong.sizeof * 8;
}

size_t count(E)() pure nothrow
if (is(E == enum))
{
    size_t res;
    foreach (i; EnumMembers!E)
        ++res;
    return res;    
}

/** Detect whether an enum is of integral type and has distinct bit flag values
    Ex: enum E {e1 = 1 << 0, e2 = 1 << 1,... }
*/
template isBitEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isBitEnum = (E.min > 0) &&
        {
            ulong values;
            foreach (i; EnumMembers!E)
            {
                if ((values & i) != 0)
                    return false;
                values |= i;
            }
            return count!E <= maxBits();
        }();
    }
    else
    {
        enum isBitEnum = false;
    }
}

/** Detect whether an enum is of integral type and has increasing values
    Ex: enum E {e1 = 1, e2 = 2, e3 = 10,... }
*/
template isOrderedEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isOrderedEnum =
        {
            auto prev = E.min;
            foreach (i; EnumMembers!E)
            {
                if (i != E.min && i <= prev)
                    return false;
                prev = i;
            }
            return count!E <= maxBits();
        }();
    }
    else
    {
        enum isOrderedEnum = false;
    }
}

/** Detect whether an enum is of integral type and has increasing sequence values
    Ex: enum E {e1 = 0, e2 = 1, e3 = 2,... }
*/
template isSequenceEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isSequenceEnum = (E.min >= 0) &&
        {
            auto prev = E.min;
            foreach (i; EnumMembers!E)
            {
                if (i != E.min && i != prev + 1)
                    return false;
                prev = i;
            }
            return E.max < maxBits() && count!E <= maxBits();
        }();
    }
    else
    {
        enum isSequenceEnum = false;
    }
}

template isEnumSet(E)
{
    enum isEnumSet =
    {
        return isBitEnum!E || isOrderedEnum!E || isSequenceEnum!E;
    }();
}

template EnumSetType(E)
if (isEnumSet!E)
{
    static if (isBitEnum!E)
        static if (E.max <= uint.max)
            alias EnumSetType = uint;
        else
            alias EnumSetType = ulong;
    else
        static if (count!E() <= uint.sizeof * 8)
            alias EnumSetType = uint;
        else
            alias EnumSetType = ulong;
}

auto bit(E)(E value) pure nothrow
if (isEnumSet!E)
{
    static if (isBitEnum!E)
        return value;
    else static if (isSequenceEnum!E)
        return cast(EnumSetType!E) 1 << value;
    else
    {
        size_t at;
        foreach (i; EnumMembers!E)
        {
            if (i == value)
                return cast(EnumSetType!E) 1 << at;
            ++at;
        }
        assert(0);
    }
}

size_t ord(E)(E value) pure nothrow
if (isEnumSet!E)
{
    static if (isSequenceEnum!E)
        return value;
    else
    {
        size_t at;
        foreach (i; EnumMembers!E)
        {
            if (i == value)
                return at;
            ++at;
        }
        assert(0);
    }
}

struct EnumSet(E)
if (isEnumSet!E)
{
nothrow @safe:

public:
    enum size = count!E();

private:
    EnumSetType!E _values;

public:
    struct Range
    {
    private:
        E[size] _values;
        size_t _index, _length;

    public:
        this(EnumSet!E aValues)
        {
            if (!aValues.empty)
                foreach (i; EnumMembers!E)
                {
                    if (aValues.on(i))
                        _values[_length++] = i;
                }
        }

        void popBack()
        {
            --_length;
        }

        void popFront()
        {
            ++_index;
        }

        auto save()
        {
            return this;
        }

    @property:
        E back()
        in
        {
            assert(!empty);
        }
        body
        {
            return _values[_length - 1];
        }

        bool empty() const
        {
            return _index >= _length;
        }

        E front()
        in
        {
            assert(!empty);
        }
        body
        {
            return _values[_index];
        }
    }

public:
    this(E value)
    {
        _values = bit(value);
    }

    this(const(E)[] aValues)
    {
        _values = 0;
        foreach (i; aValues)
            _values |= bit(i);
    }

    this(V...)(V aValues)
    if (allSatisfy!(isEnumSet, V))
    {
        _values = 0;
        foreach (i; aValues)
            _values |= bit(i);
    }

    bool opCast(B: bool)() const
    {
        return _values != 0;
    }

    auto ref opAssign(E value)
    {
        _values = bit(value);
        return this;
    }

    auto ref opAssign(const(E)[] aValues)
    {
        _values = 0;
        foreach (i; aValues)
            _values |= bit(i);
        return this;
    }

    auto ref opAssign(V...)(V aValues)
    if (allSatisfy!(isEnumSet, V))
    {
        _values = 0;
        foreach (i; aValues)
            _values |= bit(i);
        return this;
    }

    auto ref opOpAssign(string op)(E value)
    if (op == "^" || op == "-" || op == "|" || op == "+")
    {
        static if (op == "^" || op == "-")
            _values &= ~bit(value);
        else static if (op == "|" || op == "+")
            _values |= bit(value);
        else
            static assert(0);

        return this;       
    }

    auto ref opOpAssign(string op)(EnumSet!E aValues)
    if (op == "^" || op == "-" || op == "|" || op == "+" || op == "&" || op == "*")
    {
        static if (op == "^" || op == "-")
            _values &= ~aValues.values;
        else static if (op == "|" || op == "+")
            _values |= aValues.values;
        else static if (op == "&" || op == "*")
            _values &= aValues.values;
        else
            static assert(0);

        return this;
    }

    auto opBinary(string op)(E value) const
    if (op == "^" || op == "-" || op == "|" || op == "+")
    {
        EnumSet!E res = this;
        return res.opOpAssign!op(value);
    }

    auto opBinary(string op)(EnumSet!E aValues) const
    if (op == "^" || op == "-" || op == "|" || op == "+" || op == "&" || op == "*")
    {
        EnumSet!E res = this;
        return res.opOpAssign!op(aValues);
    }

    bool opEquals()(auto ref const EnumSet!E aValues) const
    { 
        return _values == aValues.values;
    }

    Range opSlice() const
    {
        return Range(this);
    }

    auto ref exc(E value)
    {
        return opOpAssign!"-"(value);
    }

    auto ref inc(E value)
    {
        return opOpAssign!"+"(value);
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

    bool any(V...)(V aValues) const
    if (allSatisfy!(isEnumSet, V))
    {
        foreach (i; aValues)
        {
            if (on(i))
                return true;
        }
        return false;
    }

    pragma (inline, true)
    bool off(E value) const
    {
        return _values == 0 || (_values & bit(value)) == 0;
    }

    pragma (inline, true)
    bool on(E value) const
    {
        return _values != 0 && (_values & bit(value)) != 0;
    }

    auto ref set(E value, bool opSet)
    {
        if (opSet)
            return opOpAssign!"+"(value);
        else
            return opOpAssign!"-"(value);
    }

    /** Defines the set from a string representation
        Params:
            aValues = a string representing one or several E members separated by comma
        Returns:
            Number of failed to convert a member string
    */
    size_t fromString(const(char)[] aValues)
    {
        import std.ascii : isWhite;
        import std.conv : to;

        _values = 0;

        size_t fails, pos, len;

        len = aValues.length;

        // Skip trailing spaces
        while (len > pos && isWhite(aValues[len - 1]))
            --len;

        // Skip trailing set indicator?
        if (pos < len && aValues[len - 1] == ']')
            --len;

        // Skip preceeding spaces
        bool skipSpaces()
        {
            while (pos < len && isWhite(aValues[pos]))
                ++pos;
            return pos < len;
        }

        // Skip preceeding set indicator?
        if (skipSpaces() && aValues[pos] == '[')
            ++pos;        

        // Empty set?
        if (pos >= len)
            return 0;

        while (skipSpaces())
        {
            // Get the begin and end position for the string element
            const begin = pos;
            size_t lastSpace = size_t.max;
            while (pos < len && aValues[pos] != ',')
            {
                if (isWhite(aValues[pos]))
                {
                    if (lastSpace == size_t.max)
                        lastSpace = pos;
                }
                else if (lastSpace != size_t.max)
                    lastSpace = size_t.max;
                ++pos;
            }

            // Get the string element
            auto value = aValues[begin .. lastSpace == size_t.max ? pos : lastSpace];

            // Skip comma
            ++pos;

            try
            {
                auto toValue = to!E(value);
                inc(toValue);
             }
             catch (Exception e)
             {
                 ++fails;
             }
        }

        return fails;
    }

    ulong toHash()
    {
        return _values;
    }

    /** Returns the string representation of the set
    */
    string toString()
    {
        import std.array : Appender;
        import std.conv : to;

        if (empty)
            return "[]";

        try
        {
            size_t count;
            auto res = Appender!string();
            res.reserve(500);
            res.put('[');
            foreach(i; EnumMembers!E)
            {
                if (on(i))
                {
                    if (++count != 1)
                        res.put(',');
                    res.put(to!string(i));
                }
            }
            res.put(']');
            return res.data;
        }
        catch (Exception e)
        {
            assert(0);
        }
    }

@property:
    bool empty() const
    {
        return _values == 0;
    }

    EnumSetType!E values() const
    {
        return _values;
    }
}

struct EnumArray(E, T)
if (isEnumSet!E)
{
nothrow @safe:

public:
    enum size = count!E();

    struct Entry 
    {
        T v;
        E e;
        this(E aE, T aV)
        {
            e = aE;
            v = aV;
        }
    }

private:
    enum isEntry(TEntry) = is(TEntry == Entry);
    T[size] _values;

public:
    this(V...)(V aValues)
    if (allSatisfy!(isEntry, V))
    {
        foreach (i; aValues)
            _values[ord(i.e)] = i.v;
    }
    
    T opIndex(E aEnum) const
    { 
        return _values[ord(aEnum)]; 
    }

    T opIndexAssign(T aValue, E aEnum)
    {
        return _values[ord(aEnum)] = aValue;
    }

    T opDispatch(string aEnumName)() const
    {
        import std.conv : to;

        enum e = aEnumName.to!E;
        return _values[ord(e)];
    }

    T opDispatch(string aEnumName)(T aValue)
    {
        import std.conv : to;

        enum e = aEnumName.to!E;
        return _values[ord(e)] = aValue;
    }

    E getEnum(T aValue, E aDefault = E.min)
    {
        foreach (i; EnumMembers!E)
        {
            if (_values[ord(i)] == aValue)
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

unittest // EnumSet
{
    import std.traits : OriginalType;
    import std.stdio : writeln;
    writeln("unittest utl_enumset.EnumSet");

    //pragma(msg, size_t.sizeof * 8, '.', size_t.max);

    void Test(E)(string values)
    {
        alias EnumTestSet = EnumSet!E;

        EnumTestSet testFlags;

        assert(testFlags.values == 0);
        foreach (i; EnumMembers!E)
        {
            assert(testFlags.off(i));
            assert(!testFlags.on(i));
        }

        assert(testFlags.inc(E.one).on(E.one));
        assert(testFlags.off(E.two));
        assert(testFlags.off(E.three));

        assert(testFlags.inc(E.two).on(E.two));
        assert(testFlags.on(E.one));
        assert(testFlags.off(E.three));

        assert(testFlags.inc(E.three).on(E.three));

        assert(testFlags.values != 0);
        foreach (i; EnumMembers!E)
        {
            assert(!testFlags.off(i));
            assert(testFlags.on(i));
        }
        assert(testFlags.toString() == values, testFlags.toString());

        assert(testFlags.exc(E.one).off(E.one));
        assert(testFlags.on(E.two));
        assert(testFlags.on(E.three));

        assert(testFlags.exc(E.two).off(E.two));
        assert(testFlags.off(E.two));
        assert(testFlags.on(E.three));

        assert(testFlags.exc(E.three).off(E.three));

        assert(testFlags.values == 0);
        foreach (i; EnumMembers!E)
        {
            assert(testFlags.off(i));
            assert(!testFlags.on(i));
        }
        assert(testFlags.toString() == "[]", testFlags.toString());

        assert(testFlags.fromString(values) == 0);
        assert(testFlags.toString() == values, testFlags.toString());

        EnumTestSet testFlag1s = EnumTestSet(E.one, E.three);
        EnumTestSet testFlag2s = EnumTestSet(E.two, E.three);
        assert(testFlag1s != testFlag2s);

        EnumTestSet testFlag3s = testFlag1s * testFlag2s;
        assert(testFlag3s.toString() == "[three]", testFlag3s.toString());

        testFlag3s = testFlag1s + testFlag2s;
        assert(testFlag3s.toString() == "[one,two,three]", testFlag3s.toString());

        testFlag3s = testFlag1s - testFlag2s;
        assert(testFlag3s.toString() == "[one]", testFlag3s.toString());
    }

    enum EnumTestOrder
    {
        one = 1,
        two = 3,
        three = 32
    }

    /*
    pragma(msg, 
        "EnumTestSkip ", EnumSetType!EnumTestOrder,
        ", min: ", EnumTestOrder.min + 0, 
        ", max: ", EnumTestOrder.max + 0,
        ", count: ", count!EnumTestOrder(),
        ", isEnumSet: ", isEnumSet!(EnumTestOrder),
        ", OriginalType: ", OriginalType!EnumTestOrder);
    */

    static assert(!isBitEnum!EnumTestOrder);
    static assert(!isSequenceEnum!EnumTestOrder);
    Test!EnumTestOrder("[one,two,three]");


    enum EnumTestSequence
    {
        one,
        two,
        three
    }
    
    /*
    pragma(msg, 
        "EnumTestSequence ", EnumSetType!EnumTestSequence,
        ", min: ", EnumTestSequence.min + 0, 
        ", max: ", EnumTestSequence.max + 0,
        ", count: ", count!EnumTestSequence(),
        ", isEnumSet: ", isEnumSet!(EnumTestSequence),
        ", OriginalType: ", OriginalType!EnumTestSequence);
    */

    Test!EnumTestSequence("[one,two,three]");

    enum EnumTestBit
    {
        one = 1 << 0,
        two = 1 << 1,
        three = 1 << 2
    }

    /*
    pragma(msg, 
        "EnumTestBit ", EnumSetType!EnumTestBit,
        ", min: ", EnumTestBit.min + 0, 
        ", max: ", EnumTestBit.max + 0,
        ", count: ", count!EnumTestBit(),
        ", isEnumSet: ", isEnumSet!(EnumTestBit),
        ", OriginalType: ", OriginalType!EnumTestBit);
    */

    Test!EnumTestBit("[one,two,three]");


    enum EnumTestLimit1
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32
    }
    static assert(isEnumSet!EnumTestLimit1);
    static assert(is(EnumSetType!EnumTestLimit1 == uint));

    enum EnumTestLimit2
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32, b33, b34, b35, b36, b37, b38, b39, b40,
        b41, b42, b43, b44, b45, b46, b47, b48, b49, b50,
        b51, b52, b53, b54, b55, b56, b57, b58, b59, b60,
        b61, b62, b63, b64
    }
    static assert(isEnumSet!EnumTestLimit2);
    static assert(is(EnumSetType!EnumTestLimit2 == ulong));

    enum EnumTestFailOverSequence
    {
        b1=60,
        b2=61,
        b3=62,
        b4=63,
        b5=64
    }
    static assert(!isSequenceEnum!EnumTestFailOverSequence);

    enum EnumTestFailOverElement
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32, b33, b34, b35, b36, b37, b38, b39, b40,
        b41, b42, b43, b44, b45, b46, b47, b48, b49, b50,
        b51, b52, b53, b54, b55, b56, b57, b58, b59, b60,
        b61, b62, b63, b64, b65
    }
    static assert(!isEnumSet!EnumTestFailOverElement);
}

unittest // EnumArray
{
    import std.stdio : writeln;
    writeln("unittest utl_enumset.EnumArray");

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
