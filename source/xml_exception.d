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

module pham.xml_exception;

import std.exception : Exception;
import std.format : format;

import pham.xml_msg;

struct XmlLoc
{
public:
    // Zero based index values
    size_t line;
    size_t column;

    this(size_t aLine, size_t aColumn)
    {
        line = aLine;
        column = aColumn;
    }

    bool isSpecified() const nothrow @safe
    {
        return line != 0 || column != 0;
    }

@property:
    size_t sourceColumn() const nothrow @safe
    {
        return column + 1;
    }

    size_t sourceLine() const nothrow @safe
    {
        return line + 1;
    }
}

template XmlExceptionConstructors()
{
    this(string aMessage, Exception aNext = null)
    {
        super(aMessage, aNext);
    }

    this(string aMessage, XmlLoc aLoc, Exception aNext = null)
    {
        if (aLoc.isSpecified())
            aMessage = aMessage ~ format(XmlMessage.atLineInfo, aLoc.sourceLine, aLoc.sourceColumn);

        loc = aLoc;
        this(aMessage, aNext);
    }
}

class XmlException : Exception
{
    XmlLoc loc;

    mixin XmlExceptionConstructors;

    override string toString()
    {
        string s = super.toString();

        auto e = next;
        while (e !is null)
        {
            s ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return s;
    }
}

class XmlConvertException : XmlException
{
    mixin XmlExceptionConstructors;
}

class XmlInvalidOperationException : XmlException
{
    mixin XmlExceptionConstructors;
}

class XmlParserException : XmlException
{
    mixin XmlExceptionConstructors;
}