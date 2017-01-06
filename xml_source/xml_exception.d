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

module pham.xml_exception;

import std.exception : Exception;
import std.format : format;

import pham.xml_msg;

struct XmlLoc
{
public:
    // Zero based values
    size_t line;
    size_t column;

    this(size_t aLine, size_t aColumn)
    {
        line = aLine;
        column = aColumn;
    }

    bool isSpecified()
    {
        return (line != 0 || column != 0);
    }

@property:
    size_t sourceColumn()
    {
        return column + 1;
    }

    size_t sourceLine()
    {
        return line + 1;
    }
}

template XmlExceptionConstructors()
{
    this(string aMsg, Exception aNext = null)
    {
        super(aMsg, aNext);
    }

    this(XmlLoc aLoc, string aMsg, Exception aNext = null)
    {
        if (aLoc.isSpecified())
            this(aMsg ~ format(Message.atLineInfo, aLoc.sourceLine, aLoc.sourceColumn), aNext);
        else
            this(aMsg, aNext);

        loc = aLoc;
    }

    this(C, Args...)(in C[] fmt, Args args)
    {
        this(format(fmt, args));
    }

    this(C, Args...)(XmlLoc aLoc, in C[] fmt, Args args)
    {
        this(aLoc, format(fmt, args));
    }
}

class XmlException : Exception
{
    XmlLoc loc;

    mixin XmlExceptionConstructors;

    override string toString()
    {
        string s = super.toString();

        Throwable e = next;
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
