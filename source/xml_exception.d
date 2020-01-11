/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml_exception;

import pham.xml_msg;

@safe:

struct XmlLoc
{
public:
    // Zero based index values
    size_t line;
    size_t column;

public:
    this(size_t line, size_t column)
    {
        this.line = line;
        this.column = column;
    }

    bool isSpecified() const nothrow
    {
        return line != 0 || column != 0;
    }

    string lineMessage() const
    {
        import std.format : format;

        return format(XmlMessage.atLineInfo, sourceLine, sourceColumn);
    }

    @property size_t sourceColumn() const nothrow
    {
        return column + 1;
    }

    @property size_t sourceLine() const nothrow
    {
        return line + 1;
    }
}

template XmlExceptionConstructors()
{
    this(string message, Exception next)
    {
        super(message, next);
    }

    this(XmlLoc loc, string message, Exception next)
    {
        if (loc.isSpecified())
            message = message ~ loc.lineMessage();

        loc = loc;
        super(message, next);
    }

    this(Args...)(const(char)[] fmt, Args args) @trusted
    {
        import std.format : format;

        string msg = format(fmt, args);
        super(msg);
    }

    this(Args...)(XmlLoc loc, const(char)[] fmt, Args args) @trusted
    {
        import std.format : format;

        string msg = format(fmt, args);

        if (loc.isSpecified())
            msg = msg ~ loc.lineMessage();

        loc = loc;
        super(msg);
    }
}

class XmlException : Exception
{
public:
    XmlLoc loc;

public:
    mixin XmlExceptionConstructors;

    override string toString() @system
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
public:
    mixin XmlExceptionConstructors;
}

class XmlInvalidOperationException : XmlException
{
public:
    mixin XmlExceptionConstructors;
}

class XmlParserException : XmlException
{
public:
    mixin XmlExceptionConstructors;
}
