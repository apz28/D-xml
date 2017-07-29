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

import std.traits : hasMember;
import std.typecons : Flag, No, Yes;
import std.range.primitives : back, empty, front, popFront;

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_buffer;
import pham.xml_string;

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
if (isXmlString!S)
{
    alias C = XmlChar!S;

    const(C)[] s;
    XmlLoc loc;
    XmlEncodeMode encodeMode;
}

abstract class XmlReader(S) : XmlObject!S
{
private:
    enum isBlockReader = hasMember!(typeof(this), "nextBlock");

protected:
    const(C)[] s;
    size_t sLen, sPos, pPos;
    dchar current = 0;
    XmlLoc loc;
    static if (!is(C == dchar) && !isBlockReader)
    {
        C[6] currentCodeBuffer;
        const(C)[] currentCodes;
    }
    static if (isBlockReader)
    {
        XmlBuffer!(S, No.checkEncoded) nameBuffer;
        XmlBuffer!(S, Yes.checkEncoded) textBuffer;

        final void initBuffers()
        {
            nameBuffer = new XmlBuffer!(S, No.checkEncoded);
            textBuffer = new XmlBuffer!(S, Yes.checkEncoded);
        }
    }

    final void decode()
    in
    {
        assert(sPos < sLen);
    }
    body
    {
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
                static if (!isBlockReader)
                    currentCodes = null;

                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(Message.eInvalidUtf16Sequence1);
                else
                    throw new XmlConvertException(Message.eInvalidUtf16Sequence2 ~ format(", code=%d", errorCode));
            }

            void nextBlockUtf16()
            {
                static if (isBlockReader)
                {
                    if (!nextBlock())
                        errorUtf16(UnicodeErrorKind.eos, 0);
                }
                else
                    errorUtf16(UnicodeErrorKind.eos, 0);
            }

            wchar u = s[sPos++];
             
            if (u >= unicodeSurrogateHighBegin && u <= unicodeSurrogateHighEnd)
            {
                if (sPos >= sLen)
                    nextBlockUtf16();

                current = u;
                static if (!isBlockReader)
                    currentCodeBuffer[0] = u;

                u = s[sPos++];
                static if (!isBlockReader)
                    currentCodeBuffer[1] = u;

                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd) 
                {
                    current = ((current - unicodeSurrogateHighBegin) << unicodeHalfShift) +
                              (u - unicodeSurrogateLowBegin) + unicodeHalfBase;
                    static if (!isBlockReader)
                        currentCodes = currentCodeBuffer[0 .. 2];
                }
                else
                    errorUtf16(UnicodeErrorKind.invalidCode, u);
            }
            else 
            {
                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd)
                    errorUtf16(UnicodeErrorKind.invalidCode, u);

                current = u;
                static if (!isBlockReader)
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
                static if (!isBlockReader)
                    currentCodes = null;

                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(Message.eInvalidUtf8Sequence1); 
                else
                    throw new XmlConvertException(Message.eInvalidUtf8Sequence2 ~ format(", code=%d", errorCode));
            }

            void nextBlockUtf8()
            {
                static if (isBlockReader)
                {
                    if (!nextBlock())
                        errorUtf8(UnicodeErrorKind.eos, 0);
                }
                else
                    errorUtf8(UnicodeErrorKind.eos, 0);
            }

            char u = s[sPos++];

            if (u & 0x80)
            {
                byte count = 0;
                byte extraBytesToRead = unicodeTrailingBytesForUTF8[u];

                if (extraBytesToRead + sPos > sLen)
                {
                    static if (!isBlockReader)
                        errorUtf8(UnicodeErrorKind.eos, 0);
                }

                switch (extraBytesToRead) 
                {
                    case 5: 
                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 4;
                    case 4:
                        if (extraBytesToRead != 4 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 3;
                    case 3:
                        if (extraBytesToRead != 3 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 2;
                    case 2:
                        if (extraBytesToRead != 2 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 1;
                    case 1:
                        if (extraBytesToRead != 1 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 0;
                    case 0:
                        if (extraBytesToRead != 0 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        static if (!isBlockReader)
                            currentCodeBuffer[count++] = u;
                        break;
                    default:
                        assert(0);
                }

                current -= unicodeOffsetsFromUTF8[extraBytesToRead];
                static if (!isBlockReader)
                    currentCodes = currentCodeBuffer[0 .. count];

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
                static if (!isBlockReader)
                    currentCodes = s[sPos - 1 .. sPos];
            }
        }        
    }

    final void popFrontColumn()
    {
        loc.column += 1;
        current = 0;
        static if (!is(XmlChar!S == dchar) && !isBlockReader)
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

    pragma (inline, true)
    static bool isDocumentTypeAttributeListChoice(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '|' || c == '(' || c == ')' || isSpace(c);
    }

    pragma (inline, true)
    static bool isDeclarationAttributeNameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '?' || c == '=' || isSpace(c);
    }

    pragma (inline, true)
    static bool isDocumentTypeElementChoice(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == ']' || c == '*' || c == '+' || c == '|'
            || c == ',' || c == '(' || c == ')' || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementAttributeNameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '/' || c == '=' || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementENameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '!' || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementPNameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '?' || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementXNameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || c == '/' || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>';
    }

    pragma (inline, true)
    static bool isElementTextSeparator(dchar c) pure nothrow @safe
    {
        return c == '<';
    }

    pragma (inline, true)
    static bool isNameSeparator(dchar c) pure nothrow @safe
    {
        return c == '<' || c == '>' || isSpace(c);
    }

package:    
    pragma (inline, true)
    final bool isAnyFrontBut(dchar c)
    {
        return !empty && current != c;
    }

    pragma (inline, true)
    final bool isDeclarationNameStart()
    {
        if (empty)
            return false;
        else
        {
            immutable c = current;
            return !isDeclarationAttributeNameSeparator(c) && isNameStartC(c);
        }
    }

    pragma (inline, true)
    final bool isElementAttributeNameStart()
    {
        if (empty)
            return false;
        else
        {
            immutable c = current;
            return !isElementAttributeNameSeparator(c) && isNameStartC(c);
        }
    }

    pragma (inline, true)
    final bool isElementTextStart()
    {
        return !empty && !isElementSeparator(current);
    }

    final dchar moveFrontIf(dchar aCheckNonSpaceChar)
    {
        auto f = frontIf();
        if (f == aCheckNonSpaceChar)
        {
            popFrontColumn();
            return f;
        }
        else
            return 0;
    }

    final const(C)[] readAName(alias stopChar)(out ParseContext!S name)
    {
        name.loc = loc;
        static if (isBlockReader)
        {
            while (!empty && !stopChar(current))
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }
            name.s = nameBuffer.toStringAndClear();
        }
        else
        {
            size_t pStart = pPos; 
            while (!empty && !stopChar(current))
                popFrontColumn();
            name.s = s[pStart .. pPos];
        }

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, Message.eBlankName);

        version (unittest)
        outputXmlTraceParserF("readAName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        return name.s;
    }

    final const(C)[] readAnyName(out ParseContext!S name)
    {
        return readAName!isNameSeparator(name);
    }

    static if (!isBlockReader)
        final void readCurrent(Buffer)(Buffer buffer)
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

    final const(C)[] readDeclarationAttributeName(out ParseContext!S name)
    {
        return readAName!isDeclarationAttributeNameSeparator(name);
    }

    final const(C)[] readDocumentTypeAttributeListChoiceName(out ParseContext!S name)
    {
        return readAName!isDocumentTypeAttributeListChoice(name);
    }

    final const(C)[] readDocumentTypeElementChoiceName(out ParseContext!S name)
    {
        return readAName!isDocumentTypeElementChoice(name);
    }

    final const(C)[] readElementEName(out ParseContext!S name)
    {
        return readAName!isElementENameSeparator(name);
    }

    final const(C)[] readElementPName(out ParseContext!S name)
    {
        return readAName!isElementPNameSeparator(name);
    }

    final const(C)[] readElementXAttributeName(out ParseContext!S name)
    {
        return readAName!isElementAttributeNameSeparator(name);
    }

    final const(C)[] readElementXName(out ParseContext!S name)
    {
        return readAName!isElementXNameSeparator(name);
    }

    final void readElementXText(out XmlString!S text, out bool allWhitespaces)
    {
        allWhitespaces = true;

        static if (isBlockReader)
        {
            while (!empty && !isElementTextSeparator(current))
            {
                if (allWhitespaces && !isSpace(current))
                    allWhitespaces = false;
                readCurrent(textBuffer);
                popFront();
            }

            text = textBuffer.toXmlStringAndClear();
        }
        else
        {
            XmlEncodeMode encodedMode = XmlEncodeMode.checked;
            size_t pStart = pPos; 
            while (!empty && !isElementTextSeparator(current))
            {
                if (allWhitespaces && !isSpace(current))
                    allWhitespaces = false;
                if (encodedMode == XmlEncodeMode.checked && current == '&')
                    encodedMode = XmlEncodeMode.encoded;
                popFront();
            }

            text = XmlString!S(s[pStart .. pPos], encodedMode);
        }
    }

public:
    pragma (inline, true)
    final dchar frontIf()
    {
        return empty ? 0 : front;
    }

    pragma (inline, true)
    final dchar moveFront()
    {
        auto f = current;
        popFront();
        return f;
    }

    /** InputRange method to bring the next character to front.
        Checks internal stack first, and if empty uses primary buffer.
    */
    final void popFront()
    {
        updateLoc();
        current = 0;
        static if (!is(XmlChar!S == dchar) && !isBlockReader)
            currentCodes = null;
        empty; // Advance to next char
    }

    final const(C)[] readSpaces()
    {
        static if (isBlockReader)
        {
            while (!empty && isSpace(current))
                nameBuffer.put(moveFront());

            return nameBuffer.toStringAndClear();
        }
        else
        {
            size_t pStart = pPos; 
            while (!empty && isSpace(current))
                popFront();

            return s[pStart .. pPos];
        }
    }

    final bool readUntilMarker(out const(C)[] data, const(C)[] untilMarker)
    {
        immutable c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        readCurrent(nameBuffer);
                        popFront();
                        return true;
                    }

                    readCurrent(nameBuffer);
                    popFront();
                }

                return false;
            }

            while (!empty)
            {
                if (!readUntilChar())
                {
                    nameBuffer.clear();
                    return false;
                }

                if (nameBuffer.rightEqual(untilMarker))
                {
                    data = nameBuffer.dropBack(untilMarker.length).toStringAndClear();
                    return true;
                }
            }

            nameBuffer.clear();
        }
        else
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        popFront();
                        return true;
                    }

                    popFront();
                }

                return false;
            }

            size_t pStart = pPos;
            while (!empty)
            {
                if (!readUntilChar())
                    return false;

                if (equalRight!S(s[pStart .. pPos], untilMarker))
                {
                    data = s[pStart .. pPos - untilMarker.length];
                    return true;
                }
            }
        }

        return false;
    }

    final bool readUntilText(bool checkReservedChar)(out XmlString!S data, const(C)[] untilMarker)
    {
        immutable c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        readCurrent(textBuffer);
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (current == '<' || current == '>')
                            return false;
                    }

                    readCurrent(textBuffer);
                    popFront();
                }

                return false;
            }

            while (!empty)
            {
                if (!readUntilChar())
                {
                    textBuffer.clear();
                    return false;
                }

                if (textBuffer.rightEqual(untilMarker))
                {
                    data = textBuffer.dropBack(untilMarker.length).toXmlStringAndClear();
                    return true;
                }

                static if (checkReservedChar)
                {
                    if (current == '<' || current == '>')
                    {
                        textBuffer.clear();
                        return false;
                    }
                }
            }

            textBuffer.clear();
        }
        else
        {
            XmlEncodeMode encodedMode = XmlEncodeMode.checked;
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (current == '<' || current == '>')
                            return false;
                    }

                    if (encodedMode == XmlEncodeMode.checked && current == '&')
                        encodedMode = XmlEncodeMode.encoded;

                    popFront();
                }

                return false;
            }

            size_t pStart = pPos;
            while (!empty)
            {
                if (!readUntilChar())
                    return false;

                if (equalRight!S(s[pStart .. pPos], untilMarker))
                {
                    data = XmlString!S(s[pStart .. pPos - untilMarker.length], encodedMode);
                    return true;
                }
            
                static if (checkReservedChar)
                {
                    if (current == '<' || current == '>')
                        return false;
                }
            }
        }

        return false;
    }

    final auto skipSpaces()
    {
        while (!empty && isSpace(current))
            popFront();

        return this;
    }

@property:
    /// return empty property of InputRange
    abstract bool empty();

    /// return front property of InputRange
    pragma (inline, true)
    final dchar front() const
    {
        return current;
    }

    pragma (inline, true)
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
        sPos = pPos = 0;
        sLen = aStr.length;
        s = aStr;
    }

@property:
    pragma (inline, true)
    final override bool empty()
    {
        if (current == 0 && sPos < sLen)
        {
            pPos = sPos;
            decode();
        }

        return current == 0 && sPos >= sLen;
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

    final bool nextBlock()
    {
        if (sLen == s.length)
            s = fileHandle.rawRead(sBuffer);
        else
            s = [];
        sPos = pPos = 0;
        sLen = s.length;
        eof = sLen == 0;
        return !eof;
    }

public:
    this(string aFileName, ushort aBufferKSize = 64)
    {
        eof = false;
        sLen = sPos = pPos = 0;
        sBuffer.length = 1024 * max(aBufferKSize, 8);
        _fileName = aFileName;
        fileHandle.open(aFileName);
        static if (isBlockReader)
            initBuffers();
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
        sLen = sPos = pPos = 0;
    }

@property:
    pragma (inline, true)
    final override bool empty()
    {
        if (current == 0 && !eof)
        {
            if (sPos >= sLen && !nextBlock())
                return true;

            pPos = sPos;
            decode();
        }

        return current == 0 && eof;
    }

    final string fileName()
    {
        return _fileName;
    }
}