/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2016 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml_object;

import std.meta : allSatisfy;
import std.traits : EnumMembers, OriginalType;
import std.typecons : Flag, isBitFlagEnum;
import std.range.primitives : back, empty, front, popFront;
import std.array : Appender; 

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;

template isDLink(T)
if (is(T == class))
{
    static if (__traits(hasMember, T, "_next") && __traits(hasMember, T, "_prev"))
        enum isDLink = true;
    else
        enum isDLink = false;
}

mixin template DLink()
{
    alias TLinkNode = typeof(this);

    final TLinkNode dlinkInsertAfter(TLinkNode)(TLinkNode refNode, TLinkNode newNode)
    {
        assert(refNode !is null);
        assert(refNode._next !is null);

        newNode._next = refNode._next;
        newNode._prev = refNode;
        refNode._next._prev = newNode;
        refNode._next = newNode;
        return newNode;
    }

    final TLinkNode dlinkInsertEnd(TLinkNode)(ref TLinkNode lastNode, TLinkNode newNode)
    {
        if (lastNode is null)
        {
            newNode._next = newNode;
            newNode._prev = newNode;
        }
        else
            dlinkInsertAfter(lastNode, newNode);
        lastNode = newNode;
        return newNode;
    }

    pragma(inline, true)
    final bool dlinkHasPrev(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode)
    {
        return (checkNode !is lastNode._prev);
    }

    pragma(inline, true)
    final bool dlinkHasNext(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode)
    {
        return (checkNode !is lastNode._next);
    }

    final TLinkNode dlinkRemove(TLinkNode)(ref TLinkNode lastNode, TLinkNode oldNode)
    {
        if (oldNode._next is oldNode)
            lastNode = null;
        else
        {
            oldNode._next._prev = oldNode._prev;
            oldNode._prev._next = oldNode._next;
            if (oldNode is lastNode)
                lastNode = oldNode._prev;
        }
        oldNode._next = null;
        oldNode._prev = null;
        return oldNode;
    }
}

T singleton(T)(ref T v, T function() initiate)
if (is(T == class))
{
    if (v is null)
    {
        synchronized
        {
            if (v is null)
                v = initiate();
        }
    }

    return v;
}

struct EnumBitFlags(E) 
if (isBitFlagEnum!(E))
{
private:
    enum isBaseEnumType(T) = is(E == T);
    alias EType = OriginalType!E;

    EType values;

    static struct BitFlagNegations
    {
    @safe @nogc pure nothrow:
    private:
        EType values;

        @disable this();

        this(EType aValues)
        {
            values = aValues;
        }
    }

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
            values ^= aValue;
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
            values ^= aValues.values;
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

abstract class XmlObject(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

@property:
    final string className()
    {
        return this.classinfo.name;
    }

    final string shortClassName()
    {
        import std.array : join, split;
        import std.algorithm.iteration : filter;
        import std.string : indexOf;

        return split(className, ".").filter!(e => e.indexOf('!') < 0).join(".");
    }
}

package string getShortClassName(S)(XmlObject!S obj)
{
    if (obj is null)
        return "null";
    else
        return obj.shortClassName;
}

/**
* Mode to use for decoding.
*
* $(DDOC_ENUM_MEMBERS loose) decode, but ignore errors
* $(DDOC_ENUM_MEMBERS strict) decode, and throw exception on error
*/
enum XmlDecodeMode
{
    loose,
    strict
}

enum XmlEncodeMode
{
    check, // Text need to check for reserved char
    checked, // Text does not have reserved char
    decoded, // Text has reserved char in decoded form
    encoded, // Text has reserved char in encoded form
    none // Text should be left as-is (no encode or decode needed)
}

enum XmlBufferDefaultCapacity = 1000;

class XmlBuffer(S, bool checkEncoded) : XmlObject!S
{
public:
    alias XmlBuffer = typeof(this);

protected:
    XmlBuffer _next;
    XmlBuffer _prev;
    Appender!(C[]) _buffer;
    XmlEncodeMode _decodeOrEncodeResultMode = XmlEncodeMode.checked;

    pragma(inline, true)
    final void reserve(size_t count)
    {
        auto c = length + count;
        if (c > _buffer.capacity)
            _buffer.reserve(c + (c >> 1));
    }

public:
    XmlDecodeMode decodeMode = XmlDecodeMode.strict;

    this(size_t aCapacity = XmlBufferDefaultCapacity)
    {
        _buffer.reserve(aCapacity);
    }

    final XmlBuffer clear()
    {
        _buffer.clear();
        _decodeOrEncodeResultMode = XmlEncodeMode.checked;

        return this;
    }

    /**
    * xmlDecodes a string by unescaping all predefined XML entities.
    *
    * encode() escapes certain characters (ampersand, quote, apostrophe, less-than
    * and greater-than), and similarly, decode() unescapes them. These functions
    * are provided for convenience only. You do not need to use them when using
    * the std.xml classes, because then all the encoding and decoding will be done
    * for you automatically.
    *
    * This function xmlDecodes the entities &amp;amp;, &amp;quot;, &amp;apos;,
    * &amp;lt; and &amp;gt,
    * as well as decimal and hexadecimal entities such as &amp;#x20AC;
    *
    * If the string does not contain an ampersand, the original will be returned.
    *
    * Note that the "mode" parameter can be one of DecodeMode.NONE (do not
    * decode), DecodeMode.LOOSE (decode, but ignore errors), or DecodeMode.STRICT
    * (decode, and throw a XMLExceptionConvert in the event of an error).
    *
    * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
    *
    * Params:
    *      s = The string to be xmlDecoded
    *      mode = (optional) Mode to use for decoding. (Defaults to LOOSE).
    *
    * Throws: XMLExceptionConvert if mode == DecodeMode.STRICT and decode fails
    *
    * Returns: The xmlDecoded string
    *
    * Example:
    * --------------
    * writefln(decode("a &gt; b")); // writes "a > b"
    * --------------
    */
    final S decode(S s)
    {
        return decode(s, XmlEntityTable!S.defaultEntityTable());
    }

    final S decode(S s, in XmlEntityTable!S entityTable)
    {
        import std.string : startsWith;

        assert(entityTable !is null);

        /*
        debug (traceXmlParser)
        {
            import std.stdio : writeln;

            writefln("decode(%s)", s);
        }
        */

        S refChars;
        size_t i, lastI, mark;
        for (; i < s.length;)
        {
            if (s[i] != '&')
            {
                ++i;
                continue;
            }

            // Copy previous non-replace string
            if (lastI < i)
                put(s[lastI .. i]);

            refChars = null;
            mark = 0;
            for (size_t j = i + 1; j < s.length && mark == 0; ++j)
            {
                switch (s[j])
                {
                    case ';':
                        refChars = s[i .. j + 1];
                        mark = 1;
                        /*
                        debug (traceXmlParser)
                        {
                            import std.stdio : writeln;

                            writefln("refChars(;): %s, i: %d, j: %d", refChars, i, j);
                        }
                        */
                        break;
                    case '&':
                        refChars = s[i .. j];
                        mark = 2;
                        /*
                        debug (traceXmlParser)
                        {
                            import std.stdio : writeln;

                            writefln("refChars(&): %s, i: %d, j: %d", refChars, i, j);
                        }
                        */
                        break;
                    default:
                        break;
                }
            }

            if (mark != 1 || refChars.length <= 2)
            {
                if (decodeMode == XmlDecodeMode.strict)
                    throw new XmlConvertException(XmlLoc(0, i), Message.eUnescapeAndChar ~ " " ~ leftString(refChars, 20));

                if (mark == 0)
                {
                    lastI = i;
                    break;
                }
                else
                {
                    put(refChars);
                    i += refChars.length;
                }
            }
            else
            {
                /*
                debug (traceXmlParser)
                {
                    import std.stdio : writeln;

                    writefln("refChars(convert): %s", refChars);
                }
                */

                if (refChars[1] == '#')
                {
                    dchar c;
                    if (!convertToChar!S(refChars[2 .. $ - 1], c))
                    {
                        if (decodeMode == XmlDecodeMode.strict)
                            throw new XmlConvertException(XmlLoc(0, i), Message.eUnescapeAndChar ~ " " ~ leftString(refChars, 20));

                        put(refChars);
                    }
                    else
                        put(c);
                }
                else
                {
                    S r;
                    if (entityTable.find(refChars, r))
                        put(r);
                    else
                    {
                        if (decodeMode == XmlDecodeMode.strict)
                            throw new XmlConvertException(XmlLoc(0, i), Message.eUnescapeAndChar ~ " " ~ leftString(refChars, 20));

                        put(refChars);
                    }
                }

                i += refChars.length;
            }

            /*
            debug (traceXmlParser)
            {
                import std.stdio : writeln;

                writefln("refChars.length: %d, i: %d", refChars.length, i);
            }
            */

            lastI = i;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI .. $]);
        _decodeOrEncodeResultMode = XmlEncodeMode.decoded;

        return toString();
    }

    final XmlBuffer dropBack(size_t count)
    {
        auto len = length;
        if (len <= count)
            return clear();
        else
        {
            _buffer.shrinkTo(len - count);

            return this;
        }
    }

    /**
    * xmlEncodes a string by replacing all characters which need to be escaped with
    * appropriate predefined XML entities.
    *
    * encode() escapes certain characters (ampersand, quote, apostrophe, less-than
    * and greater-than), and similarly, decode() unescapes them. These functions
    * are provided for convenience only. You do not need to use them when using
    * the std.xml classes, because then all the encoding and decoding will be done
    * for you automatically.
    *
    * If the string is not modified, the original will be returned.
    *
    * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
    *
    * Params:
    *      s = The string to be xmlEncoded
    *
    * Returns: The xmlEncoded string
    *
    * Example:
    * --------------
    * writefln(encode("a > b")); // writes "a &gt; b"
    * --------------
    */
    final S encode(S s)
    {
        /*
        debug(traceXmlParser)
        {
            import std.stdio : writeln;

            writefln("encode(%s)", s);
        }
        */

        S r;
        size_t lastI;

        foreach (int i, c; s)
        {
            switch (c)
            {
                case '&':
                    r = "&amp;";
                    break;
                case '"':
                    r = "&quot;";
                    break;
                case '\'':
                    r = "&apos;";
                    break;
                case '<':
                    r = "&lt;";
                    break;
                case '>':
                    r = "&gt;";
                    break;
                default:
                    continue;
            }

            // Copy previous non-replace string
            put(s[lastI .. i]);

            // Replace with r
            put(r);

            lastI = i + 1;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI .. $]);
        _decodeOrEncodeResultMode = XmlEncodeMode.encoded;

        return toString();
    }

    pragma(inline, true)
    final void put(C c)
    {
        reserve(1);
        _buffer.put(c);

        static if (checkEncoded)
        {
            if (c == '&')
                _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
        }
    }

    static if (!is(C == dchar))
    {
        final void put(dchar c)
        {
            import std.encoding : encode;

            C[6] b;
            size_t n = encode(c, b);
            reserve(n);
            _buffer.put(b[0 .. n]);

            static if (checkEncoded)
            {
                if (c == '&')
                    _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
            }
        }
    }

    final void put(const(C)[] s)
    {
        reserve(s.length);
        _buffer.put(s);

        static if (checkEncoded)
        {
            if (_decodeOrEncodeResultMode != XmlEncodeMode.encoded)
            {
                foreach (c; s)
                {
                    if (c == '&')
                    {
                        _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
                        break;
                    }
                }
            }
        }
    }

    final bool rightEqual(const(C)[] s) const
    {
        auto i = length;
        auto j = s.length;
        if (i < j)
            return false;

        for (; j > 0; --i, --j)
        {
            if (_buffer.data[i - 1] != s[j - 1])
                return false;
        }

        return true;
    }

    final S rightString(size_t count) const
    {
        auto len = length;
        if (count >= len)
            return toString();
        else
            return _buffer.data[len - count .. len].idup;
    }

    final override S toString() const
    {
        return _buffer.data.idup;
    }

    pragma(inline, true)
    final S toStringAndClear()
    {
        auto s = toString();
        clear();
        return s;
    }

@property:
    final size_t capacity() const
    {
        return _buffer.capacity;
    }

    final size_t capacity(size_t newValue)
    {
        if (newValue > _buffer.capacity)
            _buffer.reserve(newValue);
        return _buffer.capacity;
    }

    final XmlEncodeMode decodeOrEncodeResultMode() const
    {
        return _decodeOrEncodeResultMode;
    }

    final bool empty() const
    {
        return (length == 0);
    }

    final size_t length() const
    {
        return _buffer.data.length;
    }
}

class XmlBufferList(S, bool checkEncoded) : XmlObject!S
{
private:
    XmlBuffer!(S, checkEncoded) last;

protected:
    mixin DLink;

public:
    version (none)  ~this()
    {
        clear();
    }

    final XmlBuffer!(S, checkEncoded) acquire()
    {
        if (last is null)
            return new XmlBuffer!(S, checkEncoded)();
        else
            return dlinkRemove(last, last);
    }

    final void clear()
    {
        while (last !is null)
            dlinkRemove(last, last);
    }

    final void release(XmlBuffer!(S, checkEncoded) b)
    {
        dlinkInsertEnd(last, b.clear());
    }

    pragma(inline, true)
    final S getAndRelease(XmlBuffer!(S, checkEncoded) b)
    {
        S r = b.toString();
        release(b);

        return r;
    }
}

class XmlEntityTable(S) : XmlObject!S
{
private:
    __gshared static XmlEntityTable!S _defaultEntityTable;

    static XmlEntityTable!S createDefaultEntityTable()
    {
        return new XmlEntityTable!S();
    }

protected:
    final void initDefault()
    {
        data["&amp;"] = "&";
        data["&apos;"] = "'";
        data["&gt;"] = ">";
        data["&lt;"] = "<";
        data["&quot;"] = "\"";
        data.rehash();
    }

public:
    S[S] data;

    this()
    {
        initDefault();
    }

    static const(XmlEntityTable!S) defaultEntityTable()
    {
        return singleton!(XmlEntityTable!S)(_defaultEntityTable, &createDefaultEntityTable);
    }

    final bool find(S encodedValue, ref S decodedValue) const
    {
        const S* r = encodedValue in data;

        if (r is null)
            return false;
        else
        {
            decodedValue = *r;
            return true;
        }
    }

    final void reset()
    {
        data = null;
        initDefault();
    }

    alias data this;
}

struct XmlString(S)
if (isXmlString!S)
{
private:
    S data;
    XmlEncodeMode mode;

public:
    this(S aStr)
    {
        this(aStr, XmlEncodeMode.check);
    }

    this(S aStr, XmlEncodeMode aMode)
    {
        data = aStr;
        mode = aMode;
    }

    auto ref opAssign(S aValue)
    {
        data = aValue;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return this;
    }

    S opCall()
    {
        return data;
    }

    S decodeText(XmlBuffer!(S, false) buffer, in XmlEntityTable!S entityTable)
    {
        assert(buffer !is null);
        assert(entityTable !is null);
        assert(needDecode());

        return buffer.decode(data, entityTable);
    }

    S encodeText(XmlBuffer!(S, false) buffer)
    {
        assert(buffer !is null);
        assert(needEncode());
        
        return buffer.encode(data);
    }

    bool needDecode()
    {
        return (data.length > 0 && (mode == XmlEncodeMode.encoded || mode == XmlEncodeMode.check));
    }

    bool needEncode()
    {
        return (data.length > 0 && (mode == XmlEncodeMode.decoded || mode == XmlEncodeMode.check));
    }

    S toString()
    {
        return data;
    }

@property:
    size_t length()
    {
        return data.length;
    }

    S value()
    {
        if (needDecode())
        {
            auto buffer = new XmlBuffer!(S, false)(data.length);
            data = buffer.decode(data);
            mode = buffer.decodeOrEncodeResultMode;
        }
        return data;
    }

    S value(S newText)
    {
        data = newText;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return newText;
    }
}

pragma(inline, true)
XmlString!S toXmlString(S, bool checkEncoded)(XmlBuffer!(S, checkEncoded) buffer)
{
    return XmlString!S(buffer.toString(), buffer.decodeOrEncodeResultMode);
}

pragma(inline, true)
XmlString!S toXmlStringAndClear(S, bool checkEncoded)(XmlBuffer!(S, checkEncoded) buffer)
{
    XmlEncodeMode m = buffer.decodeOrEncodeResultMode;
    return XmlString!S(buffer.toStringAndClear(), m);
}

unittest // XmlEntityTable.defaultEntityTable
{
    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlEntityTable.defaultEntityTable");
    }

    auto table = XmlEntityTable!string.defaultEntityTable();
    assert(table !is null);

    string s;

    assert(table.find("&amp;", s));
    assert(s == "&");

    assert(table.find("&apos;", s));
    assert(s == "'");

    assert(table.find("&gt;", s));
    assert(s == ">");

    assert(table.find("&lt;", s));
    assert(s == "<");

    assert(table.find("&quot;", s));
    assert(s == "\"");

    assert(table.find("", s) == false);
    assert(table.find("&;", s) == false);
    assert(table.find("?", s) == false);
}

unittest  // XmlBuffer.decode
{
    import std.exception : assertThrown;

    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlBuffer.decode");
    }

    string s;
    auto buffer = new XmlBuffer!(string, false)();

    // Assert that things that should work, do
    s = "hello";
    assert(buffer.clear().decode(s) is s);

    s = buffer.clear().decode("a &gt; b");
    assert(s == "a > b", s);
    assert(buffer.clear().decode("a &lt; b") == "a < b");
    assert(buffer.clear().decode("don&apos;t") == "don't");
    assert(buffer.clear().decode("&quot;hi&quot;") == "\"hi\"");
    assert(buffer.clear().decode("cat &amp; dog") == "cat & dog");
    assert(buffer.clear().decode("&#42;") == "*");
    assert(buffer.clear().decode("&#x2A;") == "*");
    assert(buffer.clear().decode("&lt;&gt;&amp;&apos;&quot;") == "<>&'\"");

    // Assert that things that shouldn't work, don't
    assertThrown!XmlConvertException(buffer.clear().decode("cat & dog"));
    assertThrown!XmlConvertException(buffer.clear().decode("a &gt b"));
    assertThrown!XmlConvertException(buffer.clear().decode("&#;"));
    assertThrown!XmlConvertException(buffer.clear().decode("&#x;"));
    assertThrown!XmlConvertException(buffer.clear().decode("&#2G;"));
    assertThrown!XmlConvertException(buffer.clear().decode("&#x2G;"));

    buffer.decodeMode = XmlDecodeMode.loose;
    s = buffer.clear().decode("cat & dog");
    assert(s == "cat & dog", s);
    assert(buffer.clear().decode("a &gt b") == "a &gt b");
    assert(buffer.clear().decode("&#;") == "&#;");
    assert(buffer.clear().decode("&#x;") == "&#x;");
    assert(buffer.clear().decode("&#2G;") == "&#2G;");
    assert(buffer.clear().decode("&#x2G;") == "&#x2G;");
}

unittest  // XmlBuffer.encode
{
    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlBuffer.encode");
    }

    string s;
    auto buffer = new XmlBuffer!(string, false)();

    s = "hello";
    assert(buffer.clear().encode(s) is s); // no change

    s = buffer.clear().encode("a > b");
    assert(s == "a &gt; b", s);
    assert(buffer.clear().encode("a < b") == "a &lt; b");
    assert(buffer.clear().encode("don't") == "don&apos;t");
    assert(buffer.clear().encode("\"hi\"") == "&quot;hi&quot;");
    assert(buffer.clear().encode("cat & dog") == "cat &amp; dog");
}
