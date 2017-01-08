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

module pham.xml_reader;

import std.typecons : Flag;
import std.range.primitives : back, empty, front, popFront;

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;

enum unicodeHalfShift = 10; 
enum unicodeHalfBase = 0x00010000;
enum unicodeHalfMask = 0x03FF;
enum unicodeSurrogateHighBegin = 0xD800;
enum unicodeSurrogateHighEnd = 0xDBFF;
enum unicodeSurrogateLowBegin = 0xDC00;
enum unicodeSurrogateLowEnd = 0xDFFF;

immutable byte[] unicodeTrailingBytesForUTF8 = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
];

immutable uint[] unicodeOffsetsFromUTF8 = [
    0x00000000, 0x00003080, 0x000E2080, 0x03C82080, 0xFA082080, 0x82082080
];

enum UnicodeErrorKind
{
    eos = 1,
    invalidCode = 2
}

package struct ParseContext(S)
{
    S s;
    XmlLoc loc;
}

alias IsCharEvent = bool function(dchar c);

pragma(inline, true)
bool isDocumentTypeAttributeListChoice(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '|' || c == '(' || c == ')' || isSpace(c);
}

pragma(inline, true)
bool isDeclarationAttributeNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '?' || c == '=' || isSpace(c);
}

pragma(inline, true)
bool isDocumentTypeElementChoice(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == ']' || c == '*' || c == '+' || c == '|'
        || c == ',' || c == '(' || c == ')' || isSpace(c);
}

pragma(inline, true)
bool isElementAttributeNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '/' || c == '=' || isSpace(c);
}

pragma(inline, true)
bool isElementENameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '!' || isSpace(c);
}

pragma(inline, true)
bool isElementPNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '?' || isSpace(c);
}

pragma(inline, true)
bool isElementXNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '/' || isSpace(c);
}

pragma(inline, true)
bool isElementSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>';
}

pragma(inline, true)
bool isElementTextSeparator(dchar c) pure nothrow @safe
{
    return c == '<';
}

pragma(inline, true)
bool isNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || isSpace(c);
}

abstract class XmlReader(S) : XmlObject!S
{
protected:
    const(C)[] s;
    size_t sLen, sPos;
    dchar current = 0;
    static if (!is(C == dchar))
    {
        C[6] currentCodes2;
        const(C)[] currentCodes;
    }
    XmlLoc loc;

    //pragma(inline, true)
    final void decode(bool delegate() nextBlock)
    {
        assert(sPos < sLen);

        static if (is(C == dchar))
        {
            current = s[sPos++];
        }
        else static if (is(C == wchar))
        {
            void errorUtf16(UnicodeErrorKind errorKind, uint errorCode)
            {
                import std.format : format;

                current = 0;
                currentCodes = null;
                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(Message.eInvalidUtf16Sequence1);
                else
                    throw new XmlConvertException(Message.eInvalidUtf16Sequence2 ~ format(", code=%d", errorCode));
            }

            wchar u = s[sPos++];
             
            if (u >= unicodeSurrogateHighBegin && u <= unicodeSurrogateHighEnd)
            {
                if (sPos >= sLen && (nextBlock == null || !nextBlock()))
                    errorUtf16(UnicodeErrorKind.eos, 0);

                current = u;
                currentCodes2[0] = u;

                u = s[sPos++];
                currentCodes2[1] = u;

                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd) 
                {
                    current = ((current - unicodeSurrogateHighBegin) << unicodeHalfShift) +
                              (u - unicodeSurrogateLowBegin) + unicodeHalfBase;
                    currentCodes = currentCodes2[0 .. 2];
                }
                else
                    errorUtf16(UnicodeErrorKind.invalidCode, u);
            }
            else 
            {
                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd)
                    errorUtf16(UnicodeErrorKind.invalidCode, u);

                current = u;
                currentCodes = s[sPos - 1 .. sPos];
            }
        }
        else
        {
            /* The following encodings are valid utf8 combinations:
             *  0xxxxxxx
             *  110xxxxx 10xxxxxx
             *  1110xxxx 10xxxxxx 10xxxxxx
             *  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
             *  111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
             *  1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
             */

            void errorUtf8(UnicodeErrorKind errorKind, uint errorCode)
            {
                import std.format : format;

                current = 0;
                currentCodes = null;
                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(Message.eInvalidUtf8Sequence1); 
                else
                    throw new XmlConvertException(Message.eInvalidUtf8Sequence2 ~ format(", code=%d", errorCode));
            }

            char u = s[sPos++];

            if (u & 0x80)
            {
                byte count = 0;
                byte extraBytesToRead = unicodeTrailingBytesForUTF8[u];

                if (extraBytesToRead + sPos > sLen && nextBlock == null)
                    errorUtf8(UnicodeErrorKind.eos, 0);

                switch (extraBytesToRead) 
                {
                    case 5: 
                        current += u;
                        current <<= 6;
                        currentCodes2[count++] = u;
                        if (sPos >= sLen && !nextBlock())
                            errorUtf8(UnicodeErrorKind.eos, 0);
                        u = s[sPos++];
                        goto case 4;
                    case 4:
                        if (extraBytesToRead != 4 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);
                        current += u;
                        current <<= 6;
                        currentCodes2[count++] = u;
                        if (sPos >= sLen && !nextBlock())
                            errorUtf8(UnicodeErrorKind.eos, 0);
                        u = s[sPos++];
                        goto case 3;
                    case 3:
                        if (extraBytesToRead != 3 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);
                        current += u;
                        current <<= 6;
                        currentCodes2[count++] = u;
                        if (sPos >= sLen && !nextBlock())
                            errorUtf8(UnicodeErrorKind.eos, 0);
                        u = s[sPos++];
                        goto case 2;
                    case 2:
                        if (extraBytesToRead != 2 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);
                        current += u;
                        current <<= 6;
                        currentCodes2[count++] = u;
                        if (sPos >= sLen && !nextBlock())
                            errorUtf8(UnicodeErrorKind.eos, 0);
                        u = s[sPos++];
                        goto case 1;
                    case 1:
                        if (extraBytesToRead != 1 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);
                        current += u;
                        current <<= 6;
                        currentCodes2[count++] = u;
                        if (sPos >= sLen && !nextBlock())
                            errorUtf8(UnicodeErrorKind.eos, 0);
                        u = s[sPos++];
                        goto case 0;
                    case 0:
                        if (extraBytesToRead != 0 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);
                        current += u;
                        currentCodes2[count++] = u;
                        break;
                    default:
                        assert(0);
                }
                current -= unicodeOffsetsFromUTF8[extraBytesToRead];
                currentCodes = currentCodes2[0 .. count];

                if (current <= dchar.max) 
                {
                    if (current >= unicodeSurrogateHighBegin && current <= unicodeSurrogateLowEnd) 
                        errorUtf8(UnicodeErrorKind.invalidCode, current);
                }
                else
                    errorUtf8(UnicodeErrorKind.invalidCode, current);
            }
            else
            {
                current = u;
                currentCodes = s[sPos - 1 .. sPos];
            }
        }        
    }

    final void popFrontColumn()
    {
        loc.column += 1;
        current = 0;
        static if (!is(XmlChar!S == dchar))
            currentCodes = null;
        empty; // Advance to next char
    }

    final void updateLoc()
    {
        if (current == 0xD) // '\n'
        {
            loc.column = 0;
            loc.line += 1;
        }
        else if (current != 0xA)
            loc.column += 1;
    }

package:
    final dchar moveFrontIf(dchar aCheckNonSpaceChar)
    {
        //assert(!isSpace(aCheckNonSpaceChar));

        auto f = frontIf();
        if (f == aCheckNonSpaceChar)
        {
            popFrontColumn();
            return f;
        }
        else
            return 0;
    }

    final S readAnyName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        name.loc = loc;
        while (!empty && !isNameSeparator(front))
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readAnyName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    //pragma(inline, true)
    final void readCurrent(XmlBuffer!(S, false) buffer)
    {
        static if (is(C == dchar))
            buffer.put(current);
        else 
        {
            if (currentCodes.length == 1)
                buffer.put(cast(C) current);
            else
                buffer.put(currentCodes);
        }
    }

    //pragma(inline, true)
    final void readCurrent(XmlBuffer!(S, true) buffer)
    {
        static if (is(C == dchar))
            buffer.put(current);
        else 
        {
            if (currentCodes.length == 1)
                buffer.put(cast(C) current);
            else
                buffer.put(currentCodes);
        }
    }

    final S readDeclarationAttributeName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        assert(!empty && !isDeclarationAttributeNameSeparator(front));

        name.loc = loc;
        do
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        while (!empty && !isDeclarationAttributeNameSeparator(front));
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readDeclarationAttributeName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    final S readDocumentTypeAttributeListChoiceName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        assert(!empty && !isDocumentTypeAttributeListChoice(front));

        name.loc = loc;
        do
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        while (!empty && !isDocumentTypeAttributeListChoice(front));
        name.s = buffer.toStringAndClear();
        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);
        return name.s;
    }

    final S readDocumentTypeElementChoiceName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        assert(!empty && !isDocumentTypeElementChoice(front));

        name.loc = loc;
        do
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        while (!empty && !isDocumentTypeElementChoice(front));
        name.s = buffer.toStringAndClear();
        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);
        return name.s;
    }

    final S readElementEName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        name.loc = loc;
        while (!empty && !isElementENameSeparator(front))
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readElementEName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    final S readElementPName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        name.loc = loc;
        while (!empty && !isElementPNameSeparator(front))
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readElementPName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    final S readElementXAttributeName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        assert(!empty && !isElementAttributeNameSeparator(front));

        name.loc = loc;
        do
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        while (!empty && !isElementAttributeNameSeparator(front));
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readElementXAttributeName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    final S readElementXName(XmlBuffer!(S, false) buffer, out ParseContext!S name)
    {
        name.loc = loc;
        while (!empty && !isElementXNameSeparator(front))
        {
            readCurrent(buffer);
            popFrontColumn();
        }
        name.s = buffer.toStringAndClear();

        version (unittest)
        outputXmlTraceParserF("readElementXName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        return name.s;
    }

    final void readElementXText(XmlBuffer!(S, true) buffer, out XmlString!S text, out bool allWhitespaces)
    {
        assert(!empty && !isElementTextSeparator(front));

        dchar c;
        allWhitespaces = true;
        do
        {
            c = current;
            readCurrent(buffer);
            popFront();
            if (allWhitespaces && !isSpace(c))
                allWhitespaces = false;
        }
        while (!empty && !isElementTextSeparator(front));

        text = buffer.toXmlStringAndClear();
    }

public:
    pragma(inline, true)
    final dchar frontIf()
    {
        return empty ? 0 : front;
    }

    pragma(inline, true)
    final dchar moveFront()
    {
        auto f = current;
        popFront();
        return f;
    }

    /** 
    InputRange method to bring the next character to front.
    Checks internal stack first, and if empty uses primary buffer.
    */
    final void popFront()
    {
        updateLoc();
        current = 0;
        static if (!is(XmlChar!S == dchar))
            currentCodes = null;
        empty; // Advance to next char
    }

    final S readSpaces(XmlBuffer!(S, false) buffer)
    {
        assert(!empty && isSpace(front));

        do
        {
            buffer.put(moveFront());
        }
        while (!empty && isSpace(front));

        return buffer.toStringAndClear();
    }

    version(none)
    final auto readUntil(XmlBuffer!(S, false) buffer, IsCharEvent untilChar)
    {
        while (!empty && !untilChar(front))
        {
            readCurrent(buffer);
            popFront();
        }

        return buffer;
    }

    version(none)
    final auto readUntil(XmlBuffer!(S, true) buffer, IsCharEvent untilChar)
    {
        while (!empty && !untilChar(front))
        {
            readCurrent(buffer);
            popFront();
        }

        return buffer;
    }

    final bool readUntilAdv(bool checkReservedChar)(XmlBuffer!(S, false) buffer, dchar untilChar, bool keepUntilChar)
    {
        while (!empty)
        {
            if (current == untilChar)
            {
                if (keepUntilChar)
                    readCurrent(buffer);
                popFront();
                return true;
            }

            static if (checkReservedChar)
            {
                if (current == '<' || current == '>')
                    return false;
            }

            readCurrent(buffer);
            popFront();
        }

        return false;
    }

    final bool readUntilAdv(bool checkReservedChar)(XmlBuffer!(S, true) buffer, dchar untilChar, bool keepUntilChar)
    {
        while (!empty)
        {
            if (current == untilChar)
            {
                if (keepUntilChar)
                    readCurrent(buffer);
                popFront();
                return true;
            }

            static if (checkReservedChar)
            {
                if (current == '<' || current == '>')
                    return false;
            }

            readCurrent(buffer);
            popFront();
        }

        return false;
    }

    final bool readUntilAdv(bool checkReservedChar)(XmlBuffer!(S, false) buffer, S s)
    {
        auto c = s[$ - 1];
        while (!empty)
        {
            if (!readUntilAdv!(checkReservedChar)(buffer, c, true))
                return false;

            if (buffer.rightEqual(s))
                return true;

            static if (checkReservedChar)
            {
                if (c == '<' || c == '>')
                    return false;
            }
        }

        return false;
    }

    final bool readUntilAdv(bool checkReservedChar)(XmlBuffer!(S, true) buffer, S s)
    {
        auto c = s[$ - 1];
        while (!empty)
        {
            if (!readUntilAdv!(checkReservedChar)(buffer, c, true))
                return false;

            if (buffer.rightEqual(s))
                return true;

            static if (checkReservedChar)
            {
                if (c == '<' || c == '>')
                    return false;
            }
        }

        return false;
    }

    final auto skipSpaces()
    {
        while (!empty && isSpace(front))
            popFront();

        return this;
    }

@property:
    /// return empty property of InputRange
    abstract bool empty();

    /// return front property of InputRange
    final dchar front()
    {
        return current;
    }

    static if (!is(XmlChar!S == dchar))
    {
        final const(XmlChar!S)[] fontCodes()
        {
            return currentCodes;
        }
    }

    final XmlLoc sourceLoc() const
    {
        return loc;
    }
}

class XmlStringReader(S) : XmlReader!S
{
public:
    this(const(XmlChar!S)[] aStr)
    {
        sPos = 0;
        sLen = aStr.length;
        s = aStr;
    }

@property:
    final override bool empty()
    {
        if (current == 0 && sPos < sLen)
            decode(null);

        return (current == 0 && sPos >= sLen);
    }
}

class XmlFileReader(S) : XmlReader!S
{
import std.file;
import std.stdio;
import std.algorithm.comparison : max;

protected:
    File fileHandle;
    string _fileName;
    C[] sBuffer;
    bool eof;

    final bool readNextBlock()
    {
        if (sLen == s.length)
            s = fileHandle.rawRead(sBuffer);
        else
            s = [];
        sPos = 0;
        sLen = s.length;
        eof = (sLen == 0);
        return !eof;
    }

public:
    this(string aFileName, ushort aBufferKSize = 64)
    {
        eof = false;
        sPos = 0;
        sLen = 0;
        sBuffer.length = 1024 * max(aBufferKSize, 8);
        _fileName = aFileName;
        fileHandle.open(aFileName);
    }

    ~this()
    {
        close();
    }

    final void close()
    {
        if (fileHandle.isOpen())
            fileHandle.close();
        eof = true;
        sLen = sPos = 0;
    }

@property:
    final override bool empty()
    {
        if (current == 0 && !eof)
        {
            if (sPos >= sLen && !readNextBlock())
                return true;

            decode(&readNextBlock);
        }

        return (current == 0 && eof);
    }

    final string fileName()
    {
        return _fileName;
    }
}