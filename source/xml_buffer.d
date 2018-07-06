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

module pham.xml_buffer;

import std.typecons : Flag, No, Yes;
import std.array : Appender; 

import pham.utl_dlinklist;

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_entity_table;

enum XmlBufferDefaultCapacity = 1000;

/** Mode to use for decoding.
    $(XmlDecodeMode.loose) Decode but ignore error
    $(XmlDecodeMode.strict) Decode and throw exception on error
*/
enum XmlDecodeMode
{
    loose,
    strict
}

/** A state if a string if it has an reserved xml character
    $(XmlEncodeMode.check) A text need to be checked for reserved char
    $(XmlEncodeMode.checked) A text is already checked and it does not have reserved character
    $(XmlEncodeMode.decoded) A text has reserved character in decoded form
    $(XmlEncodeMode.encoded) A text has reserved char in encoded form
    $(XmlEncodeMode.none) A text should be left as-is and no need to do encode or decode check
*/
enum XmlEncodeMode
{
    check, 
    checked, 
    decoded, 
    encoded, 
    none 
}

class XmlBuffer(S = string, Flag!"checkEncoded" checkEncoded = No.checkEncoded) : XmlObject!S
{
public:
    alias XmlBuffer = typeof(this);

package:
    XmlBuffer _next;
    XmlBuffer _prev;

protected:
    Appender!(C[]) _buffer;
    XmlEncodeMode _decodeOrEncodeResultMode = XmlEncodeMode.checked;

    pragma (inline, true)
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

    final XmlBuffer clear() nothrow @safe
    {
        _buffer.clear();
        _decodeOrEncodeResultMode = XmlEncodeMode.checked;

        return this;
    }

    /** Decode a string. s, by unescaping all predefined XML entities.    
        This function decode the entities "&amp;amp;", "&amp;quot;", "&amp;apos;",
        "&amp;lt;" and "&amp;gt", as well as decimal and hexadecimal entities 
        such as &amp;#x20AC;
    
        Standards:
            $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
    
        Params:
            s = The string to be decoded
    
        Throws:
            XMLExceptionConvert if decode fails
    
        Returns: 
            The XML decoded string
    
        Example:
            writeln(decode("a &gt; b")); // writes "a > b"
    */
    final const(C)[] decode(const(C)[] s)
    {
        return decode(s, XmlEntityTable!S.defaultEntityTable());
    }

    /** Decode a string, s, by unescaping all passed in entities in entityTable.    
        This function decode the entities "&amp;amp;", "&amp;quot;", "&amp;apos;",
        "&amp;lt;" and "&amp;gt", as well as decimal and hexadecimal entities 
        such as &amp;#x20AC;
    
        Params:
            s = The string to be decoded
    
        Throws:
            XMLExceptionConvert if decode fails
    
        Returns: 
            The XML decoded string
    
        Example:
            writeln(decode("a &gt; b")); // writes "a > b"
    */
    final const(C)[] decode(const(C)[] s, in XmlEntityTable!S entityTable)
    {
        import std.string : startsWith;

        assert(entityTable !is null);

        version (none)
        version (unittest)
        writefln("decode(%s)", s);

        const(C)[] refChars;
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

                        version (none)
                        version (unittest)
                        outputXmlTraceParserF("refChars(;): %s, i: %d, j: %d", refChars, i, j);

                        break;
                    case '&':
                        refChars = s[i .. j];
                        mark = 2;

                        version (none)
                        version (unittest)
                        writefln("refChars(&): %s, i: %d, j: %d", refChars, i, j);

                        break;
                    default:
                        break;
                }
            }

            if (mark != 1 || refChars.length <= 2)
            {
                if (decodeMode == XmlDecodeMode.strict)
                {
                    auto msg = XmlMessage.eUnescapeAndChar ~ " " ~ 
                        toUTF!(S, string)(leftString!S(refChars, 20).idup);
                    throw new XmlConvertException(msg.idup, XmlLoc(0, i));
                }

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
                version (none)
                version (unittest)
                writefln("refChars(convert): %s", refChars);

                if (refChars[1] == '#')
                {
                    dchar c;
                    if (!convertToChar!S(refChars[2 .. $ - 1], c))
                    {
                        if (decodeMode == XmlDecodeMode.strict)
                        {
                            auto Msg = XmlMessage.eUnescapeAndChar ~ " " ~ 
                                toUTF!(S, string)(leftString!S(refChars, 20).idup);
                            throw new XmlConvertException(Msg.idup, XmlLoc(0, i));
                        }

                        put(refChars);
                    }
                    else
                        put(c);
                }
                else
                {
                    const(C)[] r;
                    if (entityTable.find(refChars, r))
                        put(r);
                    else
                    {
                        if (decodeMode == XmlDecodeMode.strict)
                        {
                            auto msg = XmlMessage.eUnescapeAndChar ~ " " ~
                                toUTF!(S, string)(leftString!S(refChars, 20).idup);
                            throw new XmlConvertException(msg.idup, XmlLoc(0, i));
                        }

                        put(refChars);
                    }
                }

                i += refChars.length;
            }

            version (none)
            version (unittest)
            writefln("refChars.length: %d, i: %d", refChars.length, i);

            lastI = i;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI .. $]);
        _decodeOrEncodeResultMode = XmlEncodeMode.decoded;

        return value();
    }

    /** Truncates this buffer, count of elements and returns itself. 
        If count is greater then the length, it will clear the buffer
    
        Params:
            count = how many elements to be truncated from the righ
    
        Returns: 
            The itself   
    */
    final XmlBuffer dropBack(size_t count) nothrow @safe
    {
        auto len = length;
        if (len <= count)
            return clear();
        else
        {
            try
            {
                _buffer.shrinkTo(len - count);
            }
            catch (Exception e)
            {
                assert(0);
            }

            return this;
        }
    }

    /** Encodes a string by replacing all characters which need to be escaped with
        appropriate predefined XML entities.
    
        encode() escapes certain characters (ampersand, quote, apostrophe, less-than
        and greater-than)
    
        If the string is not modified, the original will be returned.
    
        Standards: 
            $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
    
        Params:
            s = The string to be encoded
    
        Returns: 
            The xml encoded string
    
        Example:    
            writeln(encode("a > b")); // writes "a &gt; b"    
    */
    final const(C)[] encode(const(C)[] s) nothrow @safe
    {
        version (none)
        version (unittest)
        {
            writefln("encode(%s) - %s", s, value());
            scope (exit)
                writefln("encode() - %s", value());
        }

        const(C)[] r;
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
            if (i > lastI)
                put(s[lastI .. i]);

            // Replace with r
            if (r.length != 0)
            {
                put(r);
                r = null;
            }

            lastI = i + 1;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI .. $]);
        _decodeOrEncodeResultMode = XmlEncodeMode.encoded;

        return value();
    }

    /** Put a character, c, to the end of buffer
    
        Params:
            c = character to be appended at the end
    */
    pragma (inline, true)
    final void put(C c) nothrow @safe
    {
        reserve(1);
        _buffer.put(c);

        static if (checkEncoded)
        if (c == '&')
            _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
    }

    /** Put a character, c, to the end of buffer. If c is not the same type as C,
        it will convert c to arrar of C type and append them to the end
    
        Params:
            c = character to be appended at the end
    */
    static if (!is(C == dchar))
    final void put(dchar c) nothrow @safe
    {
        import std.encoding : encode;

        C[6] b;
        size_t n = encode(c, b);
        reserve(n);
        _buffer.put(b[0 .. n]);

        if (checkEncoded)
        if (c == '&')
            _decodeOrEncodeResultMode = XmlEncodeMode.encoded;        
    }

    /** Put an array of characters, s, to the end of buffer
    
        Params:
            s = array of characters to be appended at the end
    */
    final void put(const(C)[] s) nothrow @safe
    {
        reserve(s.length);
        _buffer.put(s);

        static if (checkEncoded)
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

    final bool rightEqual(const(C)[] subString) const nothrow @safe
    {
        return equalRight!S(_buffer.data, subString);
    }

    final const(C)[] rightString(size_t count) const nothrow @safe
    {
        auto len = length;
        if (count >= len)
            return value();
        else
            return _buffer.data[len - count .. len].idup;
    }

    final S value() const nothrow @safe
    {
        return _buffer.data.idup;
    }

    final S valueAndClear() nothrow @safe
    {
        auto result = _buffer.data.idup;
        clear();
        return result;
    }

@property:
    final size_t capacity() const nothrow @safe
    {
        return _buffer.capacity;
    }

    final size_t capacity(size_t newValue) nothrow @safe
    {
        if (newValue > _buffer.capacity)
            _buffer.reserve(newValue);
        return _buffer.capacity;
    }

    final XmlEncodeMode decodeOrEncodeResultMode() const nothrow @safe
    {
        return _decodeOrEncodeResultMode;
    }

    final bool empty() const nothrow @safe
    {
        return length == 0;
    }

    final size_t length() const nothrow @safe
    {
        return _buffer.data.length;
    }
}

class XmlBufferList(S = string, Flag!"checkEncoded" checkEncoded = No.checkEncoded) : XmlObject!S
{
private:
    XmlBuffer!(S, checkEncoded) last;

public:
    final XmlBuffer!(S, checkEncoded) acquire() nothrow @safe
    {
        if (last is null)
            return new XmlBuffer!(S, checkEncoded)();
        else
            return dlinkRemove(last, last);
    }

    final void clear() nothrow @safe
    {
        while (last !is null)
            dlinkRemove(last, last);
    }

    final void release(XmlBuffer!(S, checkEncoded) b) nothrow @safe
    {
        dlinkInsertEnd(last, b.clear());
    }

    pragma (inline, true)
    final S getAndRelease(XmlBuffer!(S, checkEncoded) b) nothrow @safe
    {
        auto result = b.value();
        release(b);
        return result;
    }
}

unittest  // XmlBuffer.decode
{
    import std.exception : assertThrown;

    outputXmlTraceProgress("unittest xml_buffer.XmlBuffer.decode");

    const(char)[] s;
    auto buffer = new XmlBuffer!(string, No.checkEncoded)();

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
    outputXmlTraceProgress("unittest xml_buffer.XmlBuffer.encode");

    const(XmlChar!string)[] s;
    auto buffer = new XmlBuffer!(string, No.checkEncoded)();

    s = "hello";
    assert(buffer.clear().encode(s) is s); // no change

    s = buffer.clear().encode("a > b");
    assert(s == "a &gt; b", s);
    assert(buffer.clear().encode("a < b") == "a &lt; b");
    assert(buffer.clear().encode("don't") == "don&apos;t");
    assert(buffer.clear().encode("\"hi\"") == "&quot;hi&quot;");
    assert(buffer.clear().encode("cat & dog") == "cat &amp; dog");
}