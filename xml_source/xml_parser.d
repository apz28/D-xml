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
import std.range.primitives : back, empty, front, popFront, popBack;
import std.conv : to;

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_buffer;
import pham.xml_string;
import pham.xml_reader;
import pham.xml_new;

struct XmlParser(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

private:
    alias ParseNameEvent = void delegate(ref ParseContext!S context);

    enum skipSpaceBefore = 1;
    enum skipSpaceAfter = 2;

    XmlDocument!S document;
    XmlReader!S reader;
    XmlBuffer!(S, Yes.checkEncoded) textBuffer;
    XmlNode!S[] nodeStack;

    const XmlParseOptions!S options;
    bool useSaxAttribute;
    bool useSaxElementBegin;
    bool useSaxElementEnd;
    bool useSaxOtherNode;
    
    version (unittest)
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

    pragma (inline, true)
    XmlNode!S peekNode()
    in
    {
        assert(!nodeStack.empty);
    }
    body
    {
        return nodeStack.back;
    }

    XmlNode!S popNode()
    in
    {
        assert(!nodeStack.empty);
    }
    body
    {       
        auto n = nodeStack.back;
        nodeStack.popBack();
        return n;
    }

    XmlNode!S pushNode(XmlNode!S n)
    in
    {
        assert(n !is null);
    }
    body
    {
        nodeStack ~= n;
        return n;
    }

    void parseCDATA(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseCDATA.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] data;
        if (!reader.readUntilMarker(data, "]]>"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "]]>");
            else
                throw new XmlParserException(reader.sourceLoc, Message.eExpectedStringButNotFound, "]]>");
        }

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createCDATA(data));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseComment(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseComment.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] data;
        if (!reader.readUntilMarker(data, "-->"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "-->");
            else
                throw new XmlParserException(reader.sourceLoc, Message.eExpectedStringButNotFound, "-->");
        }

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createComment(data));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseDeclaration(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDeclaration.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createDeclaration());

        if (reader.skipSpaces().isDeclarationNameStart())
        {
            ParseContext!S attributeName = void;
            do
            {
                parseAttributeDeclaration(node, attributeName);
            }
            while (reader.skipSpaces().isDeclarationNameStart());
        }

        expectChar!(0)('?');
        expectChar!(0)('>');

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseAttributeDeclaration(XmlNode!S parentNode, ref ParseContext!S contextName)
    {
        version (unittest)
        {
            outputXmlTraceParserF0("%sparseAttributeDeclaration: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readDeclarationAttributeName(contextName);
        if (options.validate)
        {
            if (!isName!(S, No.allowEmpty)(name))
                throw new XmlParserException(contextName.loc, Message.eInvalidName, name);
            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, Message.eAttributeDuplicated, name);
        }

        version (unittest)
        outputXmlTraceParserF("'%s'", name);

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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDocumentType.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;
        XmlNode!S documentTypeNode;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();

        if (reader.skipSpaces().isAnyFrontBut('['))
        {
            const(C)[] systemOrPublic;
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
                        auto entityReferenceName = reader.readAnyName(localContext);
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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDocumentTypeAttributeList.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();
        auto node = cast(XmlDocumentTypeAttributeList!S) parentNode.appendChild(document.createDocumentTypeAttributeList(name));

        while (reader.skipSpaces().isAnyFrontBut('>'))
            parseDocumentTypeAttributeListItem(node);

        expectChar!(0)('>');

        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseDocumentTypeAttributeListItem(XmlDocumentTypeAttributeList!S attributeList)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDocumentTypeAttributeListItem", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;
        XmlString!S defaultText;
        const(C)[] type, defaultType;
        const(C)[][] typeItems;

        auto name = reader.skipSpaces().readAnyName(localContext);

        // EnumerateType
        if (reader.skipSpaces().moveFrontIf('('))
        {
            while (reader.skipSpaces().isAnyFrontBut(')'))
            {
                typeItems ~= reader.readDocumentTypeAttributeListChoiceName(localContext);
                reader.skipSpaces().moveFrontIf('|');
            }
            expectChar!(0)(')');
        }
        else
        {
            type = reader.readAnyName(localContext);

            if (type == XmlConst.notation)
            {
                expectChar!(skipSpaceBefore)('(');
                while (reader.skipSpaces().isAnyFrontBut(')'))
                {
                    typeItems ~= reader.readDocumentTypeAttributeListChoiceName(localContext);
                    reader.skipSpaces().moveFrontIf('|');
                }
                expectChar!(0)(')');
            }
        }

        if (reader.skipSpaces().frontIf == '#')
        {
            defaultType = reader.readAnyName(localContext);

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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDocumentTypeElement.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();
        auto node = document.createDocumentTypeElement(name);
        parentNode.appendChild(node);

        if (reader.skipSpaces().moveFrontIf('('))
        {
            parseDocumentTypeElementChoice(node, node.appendChoice(""));
        }
        else
        {
            auto choice = reader.readAnyName(localContext);

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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseDocumentTypeElementChoice", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;
        XmlDocumentTypeElementItem!S last;
        bool done;

        while (!done && reader.skipSpaces().isAnyFrontBut(')'))
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
                    auto choice = reader.readDocumentTypeElementChoiceName(localContext);
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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseElement(%c)", indentString(), reader.front);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S tagName = void;

        auto c = reader.front;
        if (c == '?')
        {
            reader.popFront();
            if (reader.readElementPName(tagName) == "xml")
                parseDeclaration(tagName);
            else
                parseProcessingInstruction(tagName);
        }
        else if (c == '!')
        {
            reader.popFront();
            reader.readElementEName(tagName);
            if (tagName.s == "--")
                parseComment(tagName);
            else if (tagName.s == "[CDATA[")
                parseCDATA(tagName);
            else if (tagName.s == "DOCTYPE")
                parseDocumentType(tagName);
            else if (tagName.s == "ENTITY")
                parseEntity(tagName);
            else if (tagName.s == "ATTLIST")
                parseDocumentTypeAttributeList(tagName);
            else if (tagName.s == "ELEMENT")
                parseDocumentTypeElement(tagName);
            else if (tagName.s == "NOTATION")
                parseNotation(tagName);
            else
                throw new XmlParserException(tagName.loc, Message.eInvalidName, '!' ~ tagName.s);
        }
        else
        {
            reader.readElementXName(tagName);
            parseElementX(tagName);
        }
    }

    void parseEntity(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseEntity.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;
        XmlString!S publicId, text;
        const(C)[] systemOrPublic, notationName;
        bool reference;

        if (reader.skipSpaces().moveFrontIf('%'))
        {
            reference = true;
            reader.skipSpaces();
        }

        auto name = reader.readAnyName(localContext);

        if ("\"'".indexOf(reader.skipSpaces().frontIf()) >= 0)
        {
            text = parseQuotedValue();
        }
        else
        {
            parseExternalId(systemOrPublic, publicId, text, false);

            if (!reference && reader.skipSpaces().isAnyFrontBut('>'))
            {
                const(C)[] nData = reader.readAnyName(localContext);
                if (nData != XmlConst.nData)
                    throw new XmlParserException(localContext.loc,
                        Message.eExpectedStringButString, XmlConst.nData, nData);

                notationName = reader.skipSpaces().readAnyName(localContext);
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
        version (unittest)
        {
            outputXmlTraceParserF("%sparseElementX.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto name = tagName.s;
        if (options.validate && !isName!(S, No.allowEmpty)(name))
            throw new XmlParserException(tagName.loc, Message.eInvalidName, name);

        auto element = cast(XmlElement!S) pushNode(peekNode().appendChild(document.createElement(name)));
        if (useSaxElementBegin)
            options.onSaxElementNodeBegin(element);

        if (reader.skipSpaces().isElementAttributeNameStart())
        {
            ParseContext!S attributeName = void;
            do
            {
                parseElementXAttribute(element, attributeName);
            }
            while (reader.skipSpaces().isElementAttributeNameStart());
        }

        if (reader.moveFrontIf('>'))
        {
            if (reader.isElementTextStart())
                parseElementXText(element);

            expectChar!(0)('<');
            while (reader.isAnyFrontBut('/'))
            {
                parseElement();

                if (reader.isElementTextStart())
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
        version (unittest)
        {
            outputXmlTraceParserF0("%sparseElementXAttribute: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readElementXAttributeName(contextName);
        if (options.validate)
        {
            if (!isName!(S, No.allowEmpty)(name))
                throw new XmlParserException(contextName.loc, Message.eInvalidName, name);
            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, Message.eAttributeDuplicated, name);
        }

        version (unittest)
        outputXmlTraceParserF("'%s'", name);

        expectChar!(skipSpaceBefore | skipSpaceAfter)('=');

        // Value
        XmlString!S text = parseQuotedValue();

        auto attribute = document.createAttribute(name, text);
        parentNode.appendAttribute(attribute);
        if (useSaxAttribute && !options.onSaxAttributeNode(attribute))
            parentNode.removeAttribute(attribute);
    }

    void parseElementXEnd(const(C)[] beginTagName)
    {
        version (unittest)
        outputXmlTraceParserF("%sparseElementXEnd.%s", indentString(), beginTagName);

        ParseContext!S endTagName = void;
        if (reader.readElementXName(endTagName) != beginTagName)
            throw new XmlParserException(endTagName.loc, Message.eExpectedEndName, beginTagName, endTagName.s);
        expectChar!(skipSpaceBefore)('>');

        auto element = cast(XmlElement!S) popNode();
        if (useSaxElementEnd && !options.onSaxElementNodeEnd(element))
            peekNode().removeChild(element);
    }

    void parseElementXText(XmlNode!S parentNode)
    {
        version (unittest)
        outputXmlTraceParserF0("%sparseElementXText: ", indentString());

        XmlString!S text = void;
        bool allWhitespaces = void;
        reader.readElementXText(text, allWhitespaces);

        version (unittest)
        outputXmlTraceParserF("'%s'", text.toString().leftStringIndicator!S(30));

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

        if (node && useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseExternalId(ref const(C)[] systemOrPublic, ref XmlString!S publicId,
        ref XmlString!S text, bool optionalText)
    {
        version (unittest)
        outputXmlTraceParserF("%sparseExternalId", indentString());

        ParseContext!S localContext = void;

        systemOrPublic = reader.skipSpaces().readAnyName(localContext);
        reader.skipSpaces();

        if (systemOrPublic == XmlConst.system)
            text = parseQuotedValue();
        else if (systemOrPublic == XmlConst.public_)
        {
            publicId = parseQuotedValue();
            reader.skipSpaces();

            if (!optionalText || reader.isAnyFrontBut('>'))
                text = parseQuotedValue();
        }
        else
            throw new XmlParserException(localContext.loc, Message.eExpectedOneOfStringsButString,
                XmlConst.public_ ~ " or " ~ XmlConst.system, systemOrPublic);
    }

    void parseNotation(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseNotation.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext = void;
        XmlString!S publicId, text;
        const(C)[] systemOrPublic;

        auto name = reader.skipSpaces().readAnyName(localContext);

        parseExternalId(systemOrPublic, publicId, text, true);

        expectChar!(skipSpaceBefore)('>');

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createNotation(name, systemOrPublic, publicId, text));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    void parseProcessingInstruction(ref ParseContext!S tagName)
    {
        version (unittest)
        {
            outputXmlTraceParserF("%sparseProcessingInstruction.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = tagName.s;
        if (options.validate && !isName!(S, No.allowEmpty)(name))
            throw new XmlParserException(tagName.loc, Message.eInvalidName, name);

        XmlString!S data;
        if (!reader.readUntilText!true(data, "?>"))
        {
            if (reader.empty)
                throw new XmlParserException(Message.eExpectedStringButEos, "?>");
            else
                throw new XmlParserException(reader.sourceLoc, Message.eExpectedStringButNotFound, "?>");
        }

        auto parentNode = peekNode();
        auto node = parentNode.appendChild(document.createProcessingInstruction(name, data));
        if (useSaxOtherNode && !options.onSaxOtherNode(node))
            parentNode.removeChild(node);
    }

    XmlString!S parseQuotedValue()
    {
        version (unittest)
        outputXmlTraceParserF0("%sparseQuotedValue: ", indentString());       

        auto q = expectChar!(0)("\"'");
        XmlString!S data;
        if (!reader.readUntilText!false(data, to!S(q)))
            expectChar!(0)(q);

        version (unittest)
        outputXmlTraceParserF("'%s'", data.toString().leftStringIndicator!S(30));

        return data;
    }

    void parseSpaces()
    {
        version (unittest)
        outputXmlTraceParserF("%sparseSpaces", indentString());

        auto s = reader.readSpaces();
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
        reader = aReader;
        document = aDocument;
        options = aDocument.parseOptions;
        useSaxAttribute = options.useSax && options.onSaxAttributeNode !is null;
        useSaxElementBegin = options.useSax && options.onSaxElementNodeBegin !is null;
        useSaxElementEnd = options.useSax && options.onSaxElementNodeEnd !is null;
        useSaxOtherNode = options.useSax && options.onSaxOtherNode !is null;

        textBuffer = new XmlBuffer!(S, Yes.checkEncoded);

        nodeStack.reserve(defaultXmlLevels);
        pushNode(document);
    }

    XmlDocument!S parse()
    {
        version (unittest)
        outputXmlTraceParser("parse");

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
        catch (XmlException e)
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

unittest  // XmlParser.invalid construct
{
    outputXmlTraceProgress("unittest XmlParser.invalid construct");

    void parseError(string xml)
    {
        try
        {
            auto doc = new XmlDocument!string().load("<");

            assert(0, "never reach here for parseError");
        }
        catch (XmlParserException e)
        {
        }        
    }

    parseError("<");
    parseError(">");
    parseError("</>");
    parseError("<!");
    parseError("<!>");
    parseError("<!xyz>");
}

unittest  // XmlParser.DOCTYPE
{
    outputXmlTraceProgress("unittest XmlParser.DOCTYPE");

    static immutable string xml =
q"XML
<!DOCTYPE myDoc SYSTEM "http://myurl.net/folder" [
  <!ELEMENT anyElement ANY>
  <!ENTITY replaceText "replacement text">
  <!ATTLIST requireDataFoo foo CDATA #REQUIRED>
]>
XML";

    auto doc = new XmlDocument!string().load(xml);
}

unittest  // XmlParser 
{
    import pham.xml_unittest;

    outputXmlTraceProgress("unittest XmlParser");

    auto doc = new XmlDocument!string().load(parserXml);
}

unittest  // XmlParser.navigation 
{
    import std.conv : to;
    import std.typecons : No, Yes;

    outputXmlTraceProgress("unittest XmlParser.navigation");

    static immutable string xml =
q"XML
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

    outputXmlTraceProgress("unittest XmlParser - navigation(start walk)");
    outputXmlTraceProgress("check doc.documentDeclaration");

    assert(doc.documentDeclaration !is null);
    assert(doc.documentDeclaration.innerText = "version=\"1.0\" encoding=\"UTF-8\"");

    outputXmlTraceProgress("check doc.documentElement");

    assert(doc.documentElement !is null);
    assert(doc.documentElement.nodeType == XmlNodeType.element);
    assert(doc.documentElement.name == "root", doc.documentElement.name);
    assert(doc.documentElement.localName == "root", doc.documentElement.localName);

    XmlNodeList!string L = void;

    outputXmlTraceProgress("check doc.documentElement.getChildNodes(deep=true)");

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
    assert(L.front.nodeType == XmlNodeType.CDATA, to!string(L.front.nodeType));
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

    outputXmlTraceProgress("check doc.documentElement.childNodes()");
    
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
    assert(L.front.nodeType == XmlNodeType.CDATA, to!string(L.front.nodeType));
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

unittest  // XmlParser.SAX
{
    import pham.xml_unittest;

    outputXmlTraceProgress("unittest XmlParser.SAX");

    static bool processAttribute(XmlAttribute!string attribute)
    {
        // return true to keep the attribute, however if its parent node is discarded,
        // the attribute will also be discarded at the end
        // return false to discard the attribute
        return false; 
    }

    static void processElementBegin(XmlElement!string element)
    {
    }

    static bool processElementEnd(XmlElement!string element)
    {
        // return true to keep the element, however if its parent node is discarded,
        // the element will also be discarded at the end
        // return false to discard the element

        // Only keep elements with localName = "bookstore" | "book" | "title"
        auto localName = element.localName;
        return localName == "bookstore" ||
            localName == "book" ||
            localName == "title";
    }

    static bool processOtherNode(XmlNode!string node)
    {
        // return true to keep the node, however if its parent node is discarded,
        // the node will also be discarded at the end
        // return false to discard the node

        return node.nodeType == XmlNodeType.text; 
    }

    auto doc = new XmlDocument!string();
    doc.parseOptions.flags.include(XmlParseOptionFlag.useSax);
    doc.parseOptions.onSaxAttributeNode = &processAttribute;
    doc.parseOptions.onSaxElementNodeBegin = &processElementBegin;
    doc.parseOptions.onSaxElementNodeEnd = &processElementEnd;
    doc.parseOptions.onSaxOtherNode = &processOtherNode;
    
    doc.load(parserSaxXml);

    assert(doc.outerXml() == "<bookstore><book><title>Pride And Prejudice</title></book><book><title>The Handmaid's Tale</title></book></bookstore>");
}
