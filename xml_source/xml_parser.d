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

module pham.xml_parser;

import std.string : indexOf;
import std.typecons : No, Yes;
import std.range.primitives : back, empty, front, popFront, popBack; //, save, 

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_new;

private alias IsCharEvent = bool function(dchar c);

pragma(inline, true)
private bool isDocumentTypeAttributeListChoice(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '|' || c == '(' || c == ')' || isSpace(c);
}

pragma(inline, true)
private bool isDeclarationAttributeNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '?' || c == '=' || isSpace(c);
}

pragma(inline, true)
private bool isDocumentTypeElementChoice(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == ']' || c == '*' || c == '+' || c == '|'
        || c == ',' || c == '(' || c == ')' || isSpace(c);
}

pragma(inline, true)
private bool isElementAttributeNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '/' || c == '=' || isSpace(c);
}

pragma(inline, true)
private bool isElementENameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '!' || isSpace(c);
}

pragma(inline, true)
private bool isElementPNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '?' || isSpace(c);
}

pragma(inline, true)
private bool isElementXNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || c == '/' || isSpace(c);
}

pragma(inline, true)
private bool isElementSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>';
}

pragma(inline, true)
private bool isElementTextSeparator(dchar c) pure nothrow @safe
{
    return c == '<';
}

pragma(inline, true)
private bool isNameSeparator(dchar c) pure nothrow @safe
{
    return c == '<' || c == '>' || isSpace(c);
}

private struct ParseContext(S)
{
    S s;
    XmlLoc loc;
}

struct XmlParser(S)
if (isXmlString!S)
{
private:
    alias ParseNameEvent = void delegate(ref ParseContext!S context);

    enum skipSpaceBefore = 1;
    enum skipSpaceAfter = 2;

    XmlDocument!S document;
    XmlReader!S reader;
    XmlBuffer!(S, false) asIsBuffer, nameBuffer;
    XmlBuffer!(S, true) textBuffer;
    XmlNode!S[] nodeStack;

    ParseNameEvent[S] onParseElementNames;
    const XmlParseOptions!S options;
    bool useSaxAttribute;
    bool useSaxElementBegin;
    bool useSaxElementEnd;
    bool useSaxOtherNode;
    
    debug (traceXmlParser)
    {
        size_t nodeIndent;

        final string indentString()
        {
            return stringOfChar!string(' ', nodeIndent << 1);
        }
    }

    void expectChar(size_t aSkipSpaces)(dchar c)
    {
        static if ((aSkipSpaces & skipSpaceBefore))
            reader.skipSpaces();

        if (reader.empty)
            throw new XmlParserException(Message.eExpectedCharButEos, c);

        if (reader.moveFrontIf(c) != c)
            throw new XmlParserException(reader.sourceLoc, Message.eExpectedCharButChar, c, reader.front);

        static if ((aSkipSpaces & skipSpaceAfter))
            reader.skipSpaces();
    }

    dchar expectChar(size_t aSkipSpaces)(S oneOfChars)
    {
        static if ((aSkipSpaces & skipSpaceBefore))
            reader.skipSpaces();

        if (reader.empty)
            throw new XmlParserException(Message.eExpectedOneOfCharsButEos, oneOfChars);

        auto c = reader.front;

        if (oneOfChars.indexOf(c) < 0)
            throw new XmlParserException(reader.sourceLoc, Message.eExpectedOneOfCharsButChar, oneOfChars, c);

        reader.popFront();

        static if ((aSkipSpaces & skipSpaceAfter))
            reader.skipSpaces();

        return c;
    }

    void initParser()
    {
        onParseElementNames["xml"] = &parseDeclaration;
        onParseElementNames["--"] = &parseComment;
        onParseElementNames["[CDATA["] = &parseCDataSection;
        onParseElementNames["ATTLIST"] = &parseDocumentTypeAttributeList;
        onParseElementNames["DOCTYPE"] = &parseDocumentType;
        onParseElementNames["ELEMENT"] = &parseDocumentTypeElement;
        onParseElementNames["ENTITY"] = &parseEntity;
        onParseElementNames["NOTATION"] = &parseNotation;

        useSaxAttribute = options.useSax && options.onSaxAttributeNode !is null;
        useSaxElementBegin = options.useSax && options.onSaxElementNodeBegin !is null;
        useSaxElementEnd = options.useSax && options.onSaxElementNodeEnd !is null;
        useSaxOtherNode = options.useSax && options.onSaxOtherNode !is null;
    }

    pragma(inline, true)
    XmlNode!S peekNode()
    {
        assert(!nodeStack.empty);

        return nodeStack.back;
    }

    XmlNode!S popNode()
    {
        assert(!nodeStack.empty);

        auto n = nodeStack.back;
        nodeStack.popBack();
        return n;
    }

    XmlNode!S pushNode(XmlNode!S n)
    {
        nodeStack ~= n;
        return n;
    }

    void parseCDataSection(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseCDataSection.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (!reader.readUntilAdv!false(asIsBuffer, "]]>"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "]]>");
            else
                throw new XmlParserException(reader.loc, Message.eExpectedStringButNotFound, "]]>");
        }

        auto data = asIsBuffer.dropBack(3).toStringAndClear();

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createCDataSection(data));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseComment(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseComment.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (!reader.readUntilAdv!false(asIsBuffer, "-->"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "-->");
            else
                throw new XmlParserException(reader.loc, Message.eExpectedStringButNotFound, "-->");
        }

        auto text = asIsBuffer.dropBack(3).toStringAndClear();

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createComment(text));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseDeclaration(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDeclaration.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createDeclaration());

        if (!reader.skipSpaces().empty &&
            isNameStartC(reader.front) &&
            !isDeclarationAttributeNameSeparator(reader.front))
        {
            ParseContext!S attributeName;
            do
            {
                parseAttributeDeclaration(node, attributeName);
            }
            while (!reader.skipSpaces().empty &&
                   isNameStartC(reader.front) &&
                   !isDeclarationAttributeNameSeparator(reader.front));
        }

        expectChar!(0)('?');
        expectChar!(0)('>');

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseAttributeDeclaration(XmlNode!S parentNode, ref ParseContext!S contextName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writef;

            writef("%sparseAttributeDeclaration: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readDeclarationAttributeName(nameBuffer, contextName);
        if (options.validate)
        {
            if (!isName(name, No.allowEmpty))
                throw new XmlParserException(contextName.loc, Message.eInvalidName, name);
            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, Message.eAttributeDuplicated, name);
        }

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("'%s'", name);
        }

        expectChar!(skipSpaceBefore | skipSpaceAfter)('=');

        // Value
        XmlString!S text = parseQuotedValue();

        auto attribute = document.createAttribute(name, text);
        parentNode.appendAttribute(attribute);
        if (useSaxAttribute && !options.onSaxAttributeNode(attribute))
            parentNode.removeAttribute(attribute);
    }

    void parseDocumentType(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDocumentType.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlNode!S documentTypeNode;

        auto name = reader.skipSpaces().readAnyName(nameBuffer, localContext);

        auto parentNode = peekNode();

        if (!reader.skipSpaces().empty && reader.front != '[')
        {
            S systemOrPublic;
            XmlString!S publicId, text;
            parseExternalId(systemOrPublic, publicId, text, false);
            documentTypeNode = pushNode(parentNode.appendChild(document.createDocumentType(name,
                    systemOrPublic, publicId, text)));
        }

        if (reader.skipSpaces().moveFrontIf('['))
        {
            if (documentTypeNode is null)
                documentTypeNode = pushNode(parentNode.appendChild(document.createDocumentType(name)));

            bool done;
            while (!done && !reader.skipSpaces().empty)
            {
                switch (reader.front)
                {
                    case '<':
                        reader.popFront();
                        parseElement();
                        break;
                    case '%':
                        auto entityReferenceName = reader.readAnyName(nameBuffer, localContext);
                        auto node = documentTypeNode.appendChild(document.createText(entityReferenceName));
                        if (useSaxOtherNode && !options.onSaxOtherNode(node))
                            documentTypeNode.removeChild(node);
                        break;
                    default:
                        done = true;
                        break;
                }
            }

            expectChar!(0)(']');            
        }

        expectChar!(skipSpaceBefore)('>');

        if (documentTypeNode !is null)
        {
            popNode();
            if (useSaxOtherNode && !options.onSaxOtherNode(documentTypeNode))
                parentNode.removeChild(documentTypeNode);
        }
    }

    void parseDocumentTypeAttributeList(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDocumentTypeAttributeList.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;

        auto name = reader.skipSpaces().readAnyName(nameBuffer, localContext);

        auto parentNode = peekNode();
        auto node = cast(XmlDocumentTypeAttributeList!S) parentNode.appendChild(document.createDocumentTypeAttributeList(name));

        while (!reader.skipSpaces().empty && reader.front != '>')
            parseDocumentTypeAttributeListItem(node);

        expectChar!(0)('>');

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseDocumentTypeAttributeListItem(XmlDocumentTypeAttributeList!S attributeList)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDocumentTypeAttributeListItem", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S defaultText;
        S type, defaultType;
        S[] typeItems;

        auto name = reader.skipSpaces().readAnyName(nameBuffer, localContext);

        // EnumerateType
        if (reader.skipSpaces().moveFrontIf('('))
        {
            while (!reader.skipSpaces().empty && reader.front != ')')
            {
                typeItems ~= reader.readDocumentTypeAttributeListChoiceName(nameBuffer, localContext);
                reader.skipSpaces().moveFrontIf('|');
            }
            expectChar!(0)(')');
        }
        else
        {
            type = reader.readAnyName(nameBuffer, localContext);

            if (type == XmlConst.notation)
            {
                expectChar!(skipSpaceBefore)('(');
                while (!reader.skipSpaces().empty && reader.front != ')')
                {
                    typeItems ~= reader.readDocumentTypeAttributeListChoiceName(nameBuffer, localContext);
                    reader.skipSpaces().moveFrontIf('|');
                }
                expectChar!(0)(')');
            }
        }

        if (reader.skipSpaces().frontIf == '#')
        {
            defaultType = reader.readAnyName(nameBuffer, localContext);

            if (defaultType != XmlConst.fixed  &&
                defaultType != XmlConst.implied &&
                defaultType != XmlConst.required)
                throw new XmlParserException(localContext.loc, Message.eExpectedOneOfStringsButString,
                    XmlConst.fixed ~ ", " ~ XmlConst.implied ~ " or " ~ XmlConst.required,
                    defaultType);
        }

        if ("\"'".indexOf(reader.skipSpaces().frontIf()) >= 0)
            defaultText = parseQuotedValue();

        auto defType = document.createAttributeListDefType(name, type, typeItems);
        auto def = document.createAttributeListDef(defType, defaultType, defaultText);
        attributeList.appendDef(def);
    }

    void parseDocumentTypeElement(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDocumentTypeElement.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;

        auto name = reader.skipSpaces().readAnyName(nameBuffer, localContext);

        auto parentNode = peekNode();
        auto node = document.createDocumentTypeElement(name);
        parentNode.appendChild(node);

        if (reader.skipSpaces().moveFrontIf('('))
        {
            parseDocumentTypeElementChoice(node, node.appendChoice(""));
        }
        else
        {
            auto choice = reader.readAnyName(nameBuffer, localContext);

            if (choice != XmlConst.any && choice != XmlConst.empty)
                throw new XmlParserException(localContext.loc, Message.eExpectedOneOfStringsButString,
                    XmlConst.any ~ " or " ~ XmlConst.empty, choice);

            node.appendChoice(choice);
        }

        expectChar!(skipSpaceBefore)('>');

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseDocumentTypeElementChoice(XmlDocumentTypeElement!S node, XmlDocumentTypeElementItem!S parent)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseDocumentTypeElementChoice", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlDocumentTypeElementItem!S last;
        bool done;

        while (!done && !reader.skipSpaces().empty && reader.front != ')')
        {
            switch (reader.front)
            {
                case '(':
                    reader.popFront();
                    parseDocumentTypeElementChoice(node, parent.appendChoice(""));
                    break;
                case '?':
                case '*':
                case '+':
                    if (last !is null && last.multiIndicator == 0)
                        last.multiIndicator = cast(XmlChar!S) reader.moveFront();
                    else
                        throw new XmlParserException(reader.sourceLoc, Message.eMultipleTextFound, reader.front);
                    break;
                case '|':
                case ',':
                    reader.popFront();
                    break;
                case '<':
                case '>':
                case ']':
                    done = true;
                    break;
                default:
                    auto choice = reader.readDocumentTypeElementChoiceName(nameBuffer, localContext);
                    last = parent.appendChoice(choice);
                    break;
            }
        }
        expectChar!(skipSpaceBefore | skipSpaceAfter)(')');

        switch (reader.frontIf)
        {
            case '?':
            case '*':
            case '+':
                if (parent.multiIndicator == 0)
                    parent.multiIndicator = cast(XmlChar!S) reader.moveFront();
                else
                    throw new XmlParserException(reader.sourceLoc, Message.eMultipleTextFound, reader.front);
                break;
            default:
                break;
        }
    }

    void parseElement()
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseElement(%c)", indentString(), reader.front);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
            //std.stdio.stdout.writeln(tagName.s); std.stdio.stdout.flush();
        }

        ParseContext!S tagName;
        ParseNameEvent* onTagName;

        auto c = reader.front;
        if (c == '?')
        {
            reader.popFront();
            onTagName = reader.readElementPName(nameBuffer, tagName) in onParseElementNames;
        }
        else if (c == '!')
        {
            reader.popFront();
            onTagName = reader.readElementEName(nameBuffer, tagName) in onParseElementNames;
        }
        else
            onTagName = reader.readElementXName(nameBuffer, tagName) in onParseElementNames;

        if (onTagName is null)
        {
            if (c == '?')
                parseProcessingInstruction(tagName);
            else
                parseElementX(tagName);
        }
        else
            (*onTagName)(tagName);
    }

    void parseEntity(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseEntity.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S publicId, text;
        S systemOrPublic, notationName;
        bool reference;

        if (reader.skipSpaces().moveFrontIf('%'))
        {
            reference = true;
            reader.skipSpaces();
        }

        auto name = reader.readAnyName(nameBuffer, localContext);

        if ("\"'".indexOf(reader.skipSpaces().frontIf()) >= 0)
        {
            text = parseQuotedValue();
        }
        else
        {
            parseExternalId(systemOrPublic, publicId, text, false);

            if (!reference && !reader.skipSpaces().empty && reader.front != '>')
            {
                S nData = reader.readAnyName(nameBuffer, localContext);
                if (nData != XmlConst.nData)
                    throw new XmlParserException(localContext.loc,
                        Message.eExpectedStringButString, XmlConst.nData, nData);

                notationName = reader.skipSpaces().readAnyName(nameBuffer, localContext);
            }
        }

        expectChar!(skipSpaceBefore)('>');

        auto parentNode = peekNode();
        XmlNode!S node;
        if (reference)
        {
            if (systemOrPublic.length > 0)
                node = parentNode.appendChild(document.createEntityReference(name,
                        systemOrPublic, publicId, text));
            else
                node = parentNode.appendChild(document.createEntityReference(name, text));
        }
        else
        {
            if (systemOrPublic.length > 0)
                node = parentNode.appendChild(document.createEntity(name,
                        systemOrPublic, publicId, text, notationName));
            else
                node = parentNode.appendChild(document.createEntity(name, text));
        }

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseElementX(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseElementX.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto name = tagName.s;
        if (options.validate && !isName(name, No.allowEmpty))
            throw new XmlParserException(tagName.loc, Message.eInvalidName, name);

        auto element = cast(XmlElement!S) pushNode(peekNode().appendChild(document.createElement(name)));
        if (useSaxElementBegin)
            options.onSaxElementNodeBegin(element);

        if (!reader.skipSpaces().empty && 
            isNameStartC(reader.front) &&
            !isElementAttributeNameSeparator(reader.front))
        {
            ParseContext!S attributeName;
            do
            {
                parseElementXAttribute(element, attributeName);
            }
            while (!reader.skipSpaces().empty &&
                   isNameStartC(reader.front) &&
                   !isElementAttributeNameSeparator(reader.front));
        }

        if (reader.moveFrontIf('>'))
        {
            if (!reader.empty && !isElementSeparator(reader.front))
                parseElementXText(element);

            expectChar!(0)('<');
            while (!reader.empty && reader.front != '/')
            {
                parseElement();

                if (!reader.empty && !isElementSeparator(reader.front))
                    parseElementXText(element);

                expectChar!(0)('<');
            }
            expectChar!(0)('/');
            parseElementXEnd(tagName.s);
        }
        else
        {
            expectChar!(0)('/');
            expectChar!(0)('>');
            auto parentElement = cast(XmlElement!S) popNode();
            if (useSaxElementEnd && !options.onSaxElementNodeEnd(parentElement))
                peekNode().removeChild(parentElement);
        }
    }

    void parseElementXAttribute(XmlNode!S parentNode, ref ParseContext!S contextName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writef;

            writef("%sparseElementXAttribute: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readElementXAttributeName(nameBuffer, contextName);
        if (options.validate)
        {
            if (!isName(name, No.allowEmpty))
                throw new XmlParserException(contextName.loc, Message.eInvalidName, name);
            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, Message.eAttributeDuplicated, name);
        }

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("'%s'", name);
        }

        expectChar!(skipSpaceBefore | skipSpaceAfter)('=');

        // Value
        XmlString!S text = parseQuotedValue();

        auto attribute = document.createAttribute(name, text);
        parentNode.appendAttribute(attribute);
        if (useSaxAttribute && !options.onSaxAttributeNode(attribute))
            parentNode.removeAttribute(attribute);
    }

    void parseElementXEnd(S beginTagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseElementXEnd.%s", indentString(), beginTagName);
        }

        ParseContext!S endTagName;
        if (reader.readElementXName(nameBuffer, endTagName) != beginTagName)
            throw new XmlParserException(endTagName.loc, Message.eExpectedEndName, beginTagName, endTagName.s);
        expectChar!(skipSpaceBefore)('>');

        auto element = cast(XmlElement!S) popNode();
        if (useSaxElementEnd && !options.onSaxElementNodeEnd(element))
            peekNode().removeChild(element);
    }

    void parseElementXText(XmlNode!S parentNode)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writef;

            writef("%sparseElementXText: ", indentString());
        }

        XmlString!S text;
        bool allWhitespaces;
        reader.readElementXText(textBuffer, text, allWhitespaces);

        debug (traceXmlParser)
        {
            import std.stdio : writeln, writefln;

            if (allWhitespaces)
                writeln("");
            else
                writefln("'%s'", text.toString().leftStringIndicator(30));
        }

        XmlNode!S node;
        if (allWhitespaces)
        {
            if (options.preserveWhitespace)
                node = parentNode.appendChild(document.createSignificantWhitespace(text.value));
            //else
            //    node = parentNode.appendChild(document.createWhitespace(text.value));        
        }
        else
            node = parentNode.appendChild(document.createText(text));

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseExternalId(ref S systemOrPublic, ref XmlString!S publicId,
        ref XmlString!S text, bool optionalText)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseExternalId", indentString());
        }

        ParseContext!S localContext;

        systemOrPublic = reader.skipSpaces().readAnyName(nameBuffer, localContext);
        reader.skipSpaces();

        if (systemOrPublic == XmlConst.system)
            text = parseQuotedValue();
        else if (systemOrPublic == XmlConst.public_)
        {
            publicId = parseQuotedValue();
            reader.skipSpaces();

            if (!optionalText || (!reader.empty && reader.front != '>'))
                text = parseQuotedValue();
        }
        else
            throw new XmlParserException(localContext.loc, Message.eExpectedOneOfStringsButString,
                    XmlConst.public_ ~ " or " ~ XmlConst.system, systemOrPublic);
    }

    void parseNotation(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseNotation.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S publicId, text;
        S systemOrPublic;

        auto name = reader.skipSpaces().readAnyName(nameBuffer, localContext);

        parseExternalId(systemOrPublic, publicId, text, true);

        expectChar!(skipSpaceBefore)('>');

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createNotation(name, systemOrPublic, publicId, text));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseProcessingInstruction(ref ParseContext!S tagName)
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseProcessingInstruction.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = tagName.s;
        if (options.validate && !isName(name, No.allowEmpty))
            throw new XmlParserException(tagName.loc, Message.eInvalidName, name);

        if (!reader.readUntilAdv!true(textBuffer, "?>"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "?>");
            else
                throw new XmlParserException(reader.loc, Message.eExpectedStringButNotFound, "?>");
        }

        auto text = textBuffer.dropBack(2).toStringAndClear();

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createProcessingInstruction(name, text));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    XmlString!S parseQuotedValue()
    {
        debug (traceXmlParser)
        {
            import std.stdio : writef;

            writef("%sparseQuotedValue: ", indentString());
        }

        auto q = expectChar!(0)("\"'");
        if (!reader.readUntilAdv!false(textBuffer, q, false))
            expectChar!(0)(q);

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            auto s = textBuffer.toString();
            writefln("'%s'", s.leftStringIndicator(30));
        }

        return textBuffer.toXmlStringAndClear();
    }

    void parseSpaces()
    {
        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("%sparseSpaces", indentString());
        }

        auto s = reader.readSpaces(asIsBuffer);
        if (options.preserveWhitespace)
        {
            if (nodeStack.length == 1)
            {
                auto node = document.appendChild(document.createWhitespace(s));
                if (useSaxOtherNode && !options.onSaxOtherNode(node))
                    document.removeChild(node);
            }
            else
            {
                auto parentNode = peekNode();
                auto node = parentNode.appendChild(document.createSignificantWhitespace(s));        
                if (useSaxOtherNode && !options.onSaxOtherNode(node))
                    parentNode.removeChild(node);
            }
        }
    }

public:
    @disable this();

    this(XmlDocument!S aDocument, XmlReader!S aReader)
    {
        document = aDocument;
        reader = aReader;
        options = aDocument.parseOptions;

        asIsBuffer = new XmlBuffer!(S, false);
        nameBuffer = new XmlBuffer!(S, false);
        textBuffer = new XmlBuffer!(S, true);

        nodeStack.reserve(defaultXmlLevels);
        pushNode(document);
    }

    XmlDocument!S parse()
    {
        debug (traceXmlParser)
        {
            import std.stdio : writeln;

            writeln("parse");
        }

        initParser();

        try
        {
            while (!reader.empty)
            {
                if (isSpace(reader.front))
                {
                    if (nodeStack.length == 1)
                        reader.skipSpaces();
                    else
                        parseSpaces();
                    if (reader.empty)
                        break;
                }
                expectChar!(0)('<');
                parseElement();
            }
        }
        catch (Exception e)
        {
            if (reader is null || isClassType!XmlParserException(e))
                throw e;
            else
                throw new XmlParserException(reader.sourceLoc, e.msg, e);
        }

        assert(nodeStack.length > 0);

        if (nodeStack.length > 1)
            throw new XmlParserException(Message.eEos);

        return document;
    }
}

private enum unicodeHalfShift = 10; 
private enum unicodeHalfBase = 0x00010000;
private enum unicodeHalfMask = 0x03FF;
private enum unicodeSurrogateHighBegin = 0xD800;
private enum unicodeSurrogateHighEnd = 0xDBFF;
private enum unicodeSurrogateLowBegin = 0xDC00;
private enum unicodeSurrogateLowEnd = 0xDFFF;

private immutable byte[] unicodeTrailingBytesForUTF8 = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
];

private immutable uint[] unicodeOffsetsFromUTF8 = [
    0x00000000, 0x00003080, 0x000E2080, 0x03C82080, 0xFA082080, 0x82082080
];

private enum UnicodeErrorKind
{
    eos = 1,
    invalidCode = 2
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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readAnyName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readDeclarationAttributeName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readElementEName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readElementPName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readElementXAttributeName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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

        debug (traceXmlParser)
        {
            import std.stdio : writefln;

            writefln("readElementXName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d", 
                name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);
        }

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
    //import core.stdc.stdio : fread;
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

unittest  // XmlParser 
{
    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlParser");
    }

    static immutable string xml = q"XML
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
        <withAttributeOnly att1='' att2=""/>
        <withAttributeOnly2 att1="1" att2="abc"/>
        <attributeWithNP xmlns:myns="something"/>
        <withAttributeAndChild att1="&lt;&gt;&amp;&apos;&quot;" att2='with double quote ""'>
            <child/>
            <child></child>
        </withAttributeAndChild>
        <childWithText>abcd</childWithText>
        <childWithText2>
            line1
            line2
        </childWithText2>
        <myNS:nodeWithNP/>
        <!-- This is a -- comment -->
        <![CDATA[ dataSection! ]]>
    </root>
XML";

    auto doc = new XmlDocument!string().load(xml);
}

unittest  // XmlParser.DOCTYPE
{
    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlParser.DOCTYPE");
    }

    static immutable string xml = q"XML
    <!DOCTYPE myDoc SYSTEM "http://myurl.net/folder" [
        <!ELEMENT anyElement ANY>
        <!ENTITY replaceText "replacement text">
        <!ATTLIST requireDataFoo foo CDATA #REQUIRED>
    ]>
XML";

    auto doc = new XmlDocument!string().load(xml);
}

unittest  // XmlParser.navigation 
{
    import std.conv : to;
    import std.typecons : No, Yes;

    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XmlParser.navigation");
    }

    static immutable string xml = q"XML
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
        <withAttributeOnly att=""/>
        <withAttributeOnly2 att1="1" att2="abc"/>
        <attributeWithNP xmlns:myns="something"/>
        <withAttributeAndChild att1="&lt;&gt;&amp;&apos;&quot;" att2='with double quote ""'>
            <child/>
            <child></child>
        </withAttributeAndChild>
        <childWithText>abcd</childWithText>
        <childWithText2>line &amp; Text</childWithText2>
        <myNS:nodeWithNP/>
        <!-- This is a -- comment -->
        <![CDATA[ dataSection! ]]>
    </root>
XML";

    auto doc = new XmlDocument!string().load(xml);

    debug (traceXmlParser)
    {
        import std.stdio : writeln;

        writeln("\nunittest XmlParser - navigation(start walk)");

        writeln("check doc.documentDeclaration");
    }

    assert(doc.documentDeclaration !is null);
    assert(doc.documentDeclaration.innerText = "version=\"1.0\" encoding=\"UTF-8\"");

    debug (traceXmlParser)
    {
        import std.stdio : writeln;

        writeln("check doc.documentElement");
    }

    assert(doc.documentElement !is null);
    assert(doc.documentElement.nodeType == XmlNodeType.element);
    assert(doc.documentElement.name == "root", doc.documentElement.name);
    assert(doc.documentElement.localName == "root", doc.documentElement.localName);

    XmlNodeList!string L = void;

    debug (traceXmlParser)
    {
        import std.stdio : writeln;

        writeln("check doc.documentElement.getChildNodes(deep=true)");
    }

    L = doc.documentElement.getChildNodes(null, Yes.deep);

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly", L.front.name);
    assert(L.front.localName == "withAttributeOnly", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "", L.front.firstAttribute.value);
    assert(L.front.firstAttribute is L.front.lastAttribute);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly2", L.front.name);
    assert(L.front.localName == "withAttributeOnly2", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "1", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "abc", L.front.lastAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "attributeWithNP", L.front.name);
    assert(L.front.localName == "attributeWithNP", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "xmlns:myns", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "myns", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "something", L.front.firstAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeAndChild", L.front.name);
    assert(L.front.localName == "withAttributeAndChild", L.front.localName);
    assert(L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "att1", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "<>&'\"", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "with double quote \"\"", L.front.lastAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "child", L.front.name);
    assert(L.front.localName == "child", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute is null);
    assert(L.front.lastAttribute is null);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "child", L.front.name);
    assert(L.front.localName == "child", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute is null);
    assert(L.front.lastAttribute is null);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();

        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText", L.front.name);
    assert(L.front.localName == "childWithText", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "abcd", L.front.innerText);
    assert(L.front.firstChild.value == "abcd", L.front.firstChild.value);
    L.popFront();
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText2", L.front.name);
    assert(L.front.localName == "childWithText2", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "line & Text", L.front.innerText);
    assert(L.front.firstChild.value == "line & Text", L.front.firstChild.value);
    L.popFront();
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "myNS:nodeWithNP", L.front.name);
    assert(L.front.localName == "nodeWithNP", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.comment, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " This is a -- comment ", L.front.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.cDataSection, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " dataSection! ", L.front.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(L.empty);

    debug (traceXmlParser)
    {        
        import std.stdio : writeln;

        writeln("check doc.documentElement.childNodes()");
    }
    L = doc.documentElement.childNodes();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly", L.front.name);
    assert(L.front.localName == "withAttributeOnly", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "", L.front.firstAttribute.value);
    assert(L.front.firstAttribute is L.front.lastAttribute);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly2", L.front.name);
    assert(L.front.localName == "withAttributeOnly2", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "1", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "abc", L.front.lastAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "attributeWithNP", L.front.name);
    assert(L.front.localName == "attributeWithNP", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "xmlns:myns", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "myns", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "something", L.front.firstAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeAndChild", L.front.name);
    assert(L.front.localName == "withAttributeAndChild", L.front.localName);
    assert(L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "att1", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "<>&'\"", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "with double quote \"\"", L.front.lastAttribute.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText", L.front.name);
    assert(L.front.localName == "childWithText", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "abcd", L.front.innerText);
    assert(L.front.firstChild.value == "abcd", L.front.firstChild.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText2", L.front.name);
    assert(L.front.localName == "childWithText2", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "line & Text", L.front.innerText);
    assert(L.front.firstChild.value == "line & Text", L.front.firstChild.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "myNS:nodeWithNP", L.front.name);
    assert(L.front.localName == "nodeWithNP", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.comment, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " This is a -- comment ", L.front.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.cDataSection, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " dataSection! ", L.front.value);
    L.popFront();

    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(L.empty);
}
