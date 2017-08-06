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

    this(string aMsg, XmlLoc aLoc, Exception aNext = null)
    {
        if (aLoc.isSpecified())
            aMsg = aMsg ~ format(Message.atLineInfo, aLoc.sourceLine, aLoc.sourceColumn);

        this(aMsg, aNext);
        loc = aLoc;
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
