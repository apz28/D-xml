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

module pham.xml_string;

import std.typecons : Flag, No, Yes;

import pham.xml_util;
import pham.xml_entity_table;
import pham.xml_buffer;

struct XmlString(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

private:
    const(C)[] data;
    XmlEncodeMode mode;

public:
    this(const(C)[] aStr)
    {
        this(aStr, XmlEncodeMode.check);
    }

    this(const(C)[] aStr, XmlEncodeMode aMode)
    {
        data = aStr;
        mode = aMode;
    }

    auto ref opAssign(const(C)[] aValue)
    {
        data = aValue;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return this;
    }

    version (none)
    S opCall()
    {
        return data;
    }

    const(C)[] decodedText(XmlBuffer!(S, No.checkEncoded) buffer, in XmlEntityTable!S entityTable)
    {
        assert(buffer !is null);
        assert(entityTable !is null);
        assert(needDecode());

        return buffer.decode(data, entityTable);
    }

    const(C)[] encodedText(XmlBuffer!(S, No.checkEncoded) buffer)
    {
        assert(buffer !is null);
        assert(needEncode());
        
        return buffer.encode(data);
    }

    bool needDecode() const nothrow @safe
    {
        return data.length > 0 && (mode == XmlEncodeMode.encoded || mode == XmlEncodeMode.check);
    }

    bool needEncode() const nothrow @safe
    {
        return data.length > 0 && (mode == XmlEncodeMode.decoded || mode == XmlEncodeMode.check);
    }

    const(C)[] asValue() const
    {
        return data;
    }

@property:
    size_t length() const nothrow @safe
    {
        return data.length;
    }

    const(C)[] value()
    {
        if (needDecode())
        {
            auto buffer = new XmlBuffer!(S, No.checkEncoded)(data.length);
            data = buffer.decode(data);
            mode = buffer.decodeOrEncodeResultMode;
        }

        return data;
    }

    const(C)[] value(const(C)[] newText)
    {
        data = newText;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return newText;
    }
}

version (none)
pragma (inline, true)
XmlString!S toXmlString(S, Flag!"checkEncoded" checkEncoded)(XmlBuffer!(S, checkEncoded) buffer)
{
    auto m = buffer.decodeOrEncodeResultMode;
    return XmlString!S(buffer.value(), m);
}

pragma (inline, true)
XmlString!S toXmlStringAndClear(S, Flag!"checkEncoded" checkEncoded)(XmlBuffer!(S, checkEncoded) buffer)
{
    auto m = buffer.decodeOrEncodeResultMode;
    return XmlString!S(buffer.valueAndClear(), m);
}
