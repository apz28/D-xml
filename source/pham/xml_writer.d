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

module pham.xml_writer;

import std.range.primitives : back, empty, front, popFront;
import std.array : Appender;
import std.typecons : Flag, No, Yes;

import pham.xml_type;
import pham.xml_message;
import pham.xml_util;
import pham.xml_object;
import pham.xml_buffer;

@safe:

abstract class XmlWriter(S = string) : XmlObject!S
{
public:
    final void decOnlyOneNodeText() nothrow
    {
        _onlyOneNodeText--;
    }

    final void decNodeLevel() nothrow
    {
        _nodeLevel--;
    }

    final void incOnlyOneNodeText() nothrow
    {
        _onlyOneNodeText++;
    }

    final void incNodeLevel() nothrow
    {
        _nodeLevel++;
    }

    abstract void put(C c);

    abstract void put(scope const(C)[] s);

    static if (!is(C == dchar))
    {
        final void put(dchar c)
        {
            import std.encoding : encode;

            C[6] b;
            const n = encode(c, b);
            put(b[0..n]);
        }
    }

    final XmlWriter!S putLF()
    {
        version (none) version (unittest)
        outputXmlTraceParserF("putLF%d.%d()", _nodeLevel, _onlyOneNodeText);

        put('\n');

        return this;
    }

    pragma (inline, true)
    final void putIndent()
    {
        put(indentString());
    }

    final void putWithPreSpace(const(C)[] s)
    {
        put(' ');
        put(s);
    }

    final void putWithQuote(const(C)[] s)
    {
        put('"');
        put(s);
        put('"');
    }

    final void putAttribute(const(C)[] name, const(C)[] value)
    {
        put(name);
        put("=");
        putWithQuote(value);
    }

    final void putComment(const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        if (prettyOutput && text.length != 0 && !isSpace(text.front))
            put("<!-- ");
        else
            put("<!--");
        put(text);
        if (prettyOutput && text.length != 0 && !isSpace(text.back))
            put(" -->");
        else
            put("-->");

        if (prettyOutput)
            putLF();
    }

    final void putCData(const(C)[] data)
    {
        if (prettyOutput)
            putIndent();

        put("<![CDATA[");
        put(data);
        put("]]>");

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeBegin(const(C)[] name, const(C)[] publicOrSystem,
        const(C)[] publicId, const(C)[] text, Flag!"hasChild" hasChild)
    {
        if (prettyOutput)
            putIndent();

        put("<!DOCTYPE ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (text.length != 0)
        {
            put(' ');
            putWithQuote(text);
        }

        if (hasChild)
        {
            put(" [");
            if (prettyOutput)
                putLF();
        }
    }

    final void putDocumentTypeEnd(Flag!"hasChild" hasChild)
    {
        if (hasChild)
            put("]>");
        else
            put('>');

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeAttributeListBegin(const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put("<!ATTLIST ");
        put(name);
        put(' ');
    }

    final void putDocumentTypeAttributeListEnd()
    {
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeElementBegin(const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put("<!ELEMENT ");
        put(name);
        put(' ');
    }

    final void putDocumentTypeElementEnd()
    {
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putElementEmpty(const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put('<');
        put(name);
        put("/>");

        if (prettyOutput)
            putLF();
    }

    final void putElementEnd(const(C)[] name)
    {
        if (prettyOutput && !onlyOneNodeText)
            putIndent();

        put("</");
        put(name);
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putElementNameBegin(const(C)[] name, Flag!"hasAttribute" hasAttribute)
    {
        if (prettyOutput)
            putIndent();

        put('<');
        put(name);
        if (hasAttribute)
            put(' ');
        else
        {
            put('>');

            if (prettyOutput && !onlyOneNodeText)
                putLF();
        }
    }

    final void putElementNameEnd(const(C)[] name, Flag!"hasChild" hasChild)
    {
        if (hasChild)
            put('>');
        else
        {
            if (name.front == '?')
                put("?>");
            else
                put("/>");
        }

        if (prettyOutput && !onlyOneNodeText)
            putLF();
    }

    final void putEntityGeneral(const(C)[] name, const(C)[] publicOrSystem,
        const(C)[] publicId, const(C)[] notationName, const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!ENTITY ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (notationName.length != 0)
            putWithPreSpace(notationName);

        if (text.length != 0)
        {
            if (notationName == XmlConst!S.nData)
                putWithPreSpace(text);
            else
            {
                put(' ');
                putWithQuote(text);
            }
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putEntityReference(const(C)[] name, const(C)[] publicOrSystem,
        const(C)[] publicId, const(C)[] notationName, const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!ENTITY % ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (notationName.length != 0)
            putWithPreSpace(notationName);

        if (text.length != 0)
        {
            if (notationName == XmlConst!S.nData)
                putWithPreSpace(text);
            else
            {
                put(' ');
                putWithQuote(text);
            }
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putNotation(const(C)[] name, const(C)[] publicOrSystem,
        const(C)[] publicId, const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!NOTATION ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length > 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (text.length != 0)
        {
            put(' ');
            putWithQuote(text);
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putProcessingInstruction(const(C)[] target, const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<?");
        put(target);
        putWithPreSpace(text);
        put("?>");

        if (prettyOutput)
            putLF();
    }

    @property final bool onlyOneNodeText() const nothrow
    {
        return _onlyOneNodeText != 0;
    }

    @property final size_t nodeLevel() const nothrow
    {
        return _nodeLevel;
    }

    @property final bool prettyOutput() const nothrow
    {
        return _prettyOutput;
    }

protected:
    pragma (inline, true)
    final S indentString()
    {
        return stringOfChar!S(' ', _nodeLevel << 1);
    }

protected:
    size_t _nodeLevel;
    size_t _onlyOneNodeText;
    bool _prettyOutput;
}

class XmlStringWriter(S = string) : XmlWriter!S
{
public:
    this(Flag!"prettyOutput" prettyOutput,
         size_t capacity = 64000)
    {
        this(prettyOutput, new XmlBuffer!(S, No.CheckEncoded)(capacity));
    }

    this(Flag!"prettyOutput" prettyOutput, XmlBuffer!(S, No.CheckEncoded) buffer)
    {
        this._prettyOutput = prettyOutput;
        this.buffer = buffer;
    }

    final override void put(C c)
    {
        buffer.put(c);
    }

    final override void put(scope const(C)[] s)
    {
        version (none) version (unittest)
        outputXmlTraceParserF("put%d.%d('%s')", _nodeLevel, _onlyOneNodeText, s);

        buffer.put(s);
    }

protected:
    XmlBuffer!(S, No.CheckEncoded) buffer;
}

class XmlFileWriter(S = string) : XmlWriter!S
{
import std.file;
import std.stdio;
import std.algorithm.comparison : max;

public:
    this(string fileName, Flag!"prettyOutput" prettyOutput,
         ushort bufferKSize = 64)
    {
        this._prettyOutput = prettyOutput;
        this._maxBufferSize = 1024 * max(bufferKSize, 8);
        _buffer.reserve(_maxBufferSize);
        this._fileName = fileName;
        fileHandle.open(fileName, "wb");
    }

    ~this()
    {
        close();
    }

    final void close()
    {
        if (fileHandle.isOpen())
        {
            flush();
            fileHandle.close();
        }
    }

    final void flush()
    {
        if (_buffer.data.length != 0)
            doFlush();
    }

    final override void put(C c)
    {
        _buffer.put(c);
        if (_buffer.data.length >= _maxBufferSize)
            doFlush();
    }

    final override void put(scope const(C)[] s)
    {
        _buffer.put(s);
        if (_buffer.data.length >= _maxBufferSize)
            doFlush();
    }

    @property final string fileName() const nothrow
    {
        return _fileName;
    }

protected:
    final void doFlush()
    {
        fileHandle.write(_buffer.data);
        _buffer.clear();
    }

protected:
    File fileHandle;
    string _fileName;
    Appender!(C[]) _buffer;
    size_t _maxBufferSize;
}