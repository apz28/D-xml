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

module pham.xml_new;

import std.typecons : Flag, No, Yes;

import pham.xml_msg;
public import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_reader;
import pham.xml_writer;
import pham.xml_parser;

package enum defaultXmlLevels = 200;

enum XmlParseOptionFlag 
{
    none,
    preserveWhitespace = 1 << 0,
    useSax = 1 << 1,
    useSymbolTable = 1 << 2,
    validate = 1 << 3
}

struct XmlParseOptions(S)
if (isXmlString!S)
{
    alias XmlSaxAttributeEvent = bool function(XmlAttribute!S attribute);
    alias XmlSaxElementBeginEvent = void function(XmlElement!S element);
    alias XmlSaxElementEndEvent = bool function(XmlElement!S element);
    alias XmlSaxNodeEvent = bool function(XmlNode!S node);

    XmlSaxAttributeEvent onSaxAttributeNode;
    XmlSaxElementBeginEvent onSaxElementNodeBegin;
    XmlSaxElementEndEvent onSaxElementNodeEnd;
    XmlSaxNodeEvent onSaxOtherNode;

    // useSymbolTable should be off when useSax is set for faster performance
    EnumBitFlags!XmlParseOptionFlag flags = 
        EnumBitFlags!XmlParseOptionFlag(
            XmlParseOptionFlag.useSymbolTable |
            XmlParseOptionFlag.validate);

@property:
    pragma(inline, true)
    bool preserveWhitespace() const
    {
        return flags.isOn(XmlParseOptionFlag.preserveWhitespace);
    }

    pragma(inline, true)
    bool useSax() const
    {
        return flags.isOn(XmlParseOptionFlag.useSax);
    }

    pragma(inline, true)
    bool useSymbolTable() const
    {
        return flags.isOn(XmlParseOptionFlag.useSymbolTable);
    }

    pragma(inline, true)
    bool validate() const
    {
        return flags.isOn(XmlParseOptionFlag.validate);
    }
}

// Last custom type offset number 51
enum XmlNodeType
{
    unknown = 0,
    attribute = 2, /// An attribute (for example, id='123' ).
    cDataSection = 4, /// A CDATA section (for example, <![CDATA[my escaped text]]> ).
    comment = 8, /// A comment (for example, <!-- my comment --> ).
    declaration = 17, /// The XML declaration (for example, <?xml version='1.0'?> ).
    document = 9, /// A document object that, as the root of the document tree, provides access to the entire XML document.
    documentFragment = 11, /// A document fragment.
    documentType = 10, /// The document type declaration, indicated by the following tag (for example, <!DOCTYPE...> ).
    documentTypeAttributeList = 50, // An attribute-list declaration (for example, <!ATTLIST...> ).
    documentTypeElement = 51, /// An element declaration (for example, <!ELEMENT...> ).
    element = 1, /// An element (for example, <item></item> or <item/> ).
    entity = 6, /// An entity declaration (for example, <!ENTITY...> ).
    entityReference = 5, /// A reference to an entity (for example, &num; ).
    notation = 12, /// A notation in the document type declaration (for example, <!NOTATION...> ).
    processingInstruction = 7, /// A processing instruction (for example, <?pi test ?> ).
    significantWhitespace = 14, /// White space between markup in a mixed content model or white space within the xml:space="preserve" scope.
    text = 3, /// The text content of a node.
    whitespace = 13 /// White space between markup.
}

package class NameFilterContext(S) : XmlObject!S
{
public:
    S localName;
    S name;
    S namespaceUri;
    XmlDocument!S.EqualName equalName;

    @disable this();

    this(XmlDocument!S aDocument, S aName)
    {
        name = aName;
        equalName = aDocument.equalName;
    }

    this(XmlDocument!S aDocument, S aLocalName, S aNamespaceUri)
    {
        localName = aLocalName;
        namespaceUri = aNamespaceUri;
        equalName = aDocument.equalName;
    }
}

abstract class XmlNode(S) : XmlObject!S
{
protected:
    XmlDocument!S _ownerDocument;
    XmlNode!S _attrbLast;
    XmlNode!S _childLast;
    XmlNode!S _parent;
    XmlNode!S _next;
    XmlNode!S _prev;
    XmlName!S _qualifiedName;
    debug (Xml)
    {
        size_t attrbVersion;
        size_t childVersion;
    }

    this(XmlDocument!S aOwnerDocument)
    {
        _ownerDocument = aOwnerDocument;
    }

    mixin DLink;

    final void appendChildText(XmlStringWriter!S aWriter)
    {
        for (XmlNode!S i = firstChild; i !is null; i = i.nextSibling)
        {
            if (!i.hasChildNodes)
            {
                switch (i.nodeType)
                {
                    case XmlNodeType.cDataSection:
                    case XmlNodeType.significantWhitespace:
                    case XmlNodeType.text:
                    case XmlNodeType.whitespace:
                        aWriter.put(i.innerText);
                        break;
                    default:
                        break;
                }
            }
            else
                i.appendChildText(aWriter);
        }
    }

    final void checkAttribute(XmlNode!S aAttribute)
    {
        if (!isLoading())
        {
            if (aAttribute.ownerDocument !is null && aAttribute.ownerDocument !is selfOwnerDocument)
                throw new XmlException(Message.eNotAllowAppendDifDoc, "attribute");
        }

        if (isLoading() && selfOwnerDocument().parseOptions.validate && findAttribute(aAttribute.name) !is null)
            throw new XmlException(Message.eAttributeDuplicated, aAttribute.name);
    }

    final void checkChild(XmlNode!S aChild, string aOp)
    {
        if (!allowChild())
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, aOp);

        if (!allowChildType(aChild.nodeType))
            throw new XmlException(Message.eNotAllowChild, shortClassName, aOp, name, nodeType, aChild.name, aChild.nodeType);

        if (!isLoading())
        {
            if (aChild.ownerDocument !is null && aChild.ownerDocument !is selfOwnerDocument)
                throw new XmlException(Message.eNotAllowAppendDifDoc, "child");

            if (aChild is this || isAncestorNode(aChild))
                throw new XmlException(Message.eNotAllowAppendSelf);
        }
    }

    final void checkParent(XmlNode!S aNode, bool aChild, string aOp)
    {
        if (aNode._parent !is this)
            throw new XmlInvalidOperationException(Message.eInvalidOpFromWrongParent, shortClassName, aOp);

        if (aChild && aNode.nodeType == XmlNodeType.attribute)
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, aOp);
    }

    final XmlNode!S findChild(XmlNodeType aNodeType)
    {
        for (XmlNode!S i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == aNodeType)
                return i;
        }
        return null;
    }

    final void getElementById(XmlNode!S aParent, S aId, ref XmlElement!S found)
    {
        if (found is null)
        {
            const equalName = document.equalName;
            for (auto i = aParent.firstChild; i !is null; i = i.nextSibling)
            {
                if (i.nodeType == XmlNodeType.element) 
                {
                    if (equalName(i.getAttributeById(), aId))
                    {
                        found = cast(XmlElement!S) i;
                        break;
                    }
                    else
                        getElementById(i, aId, found);
                }
            }
        }
    }

    bool isLoading()
    {
        return selfOwnerDocument().isLoading();
    }

    bool isText() const
    {
        return false;
    }

    XmlDocument!S selfOwnerDocument()
    {
        return _ownerDocument;
    }

    final XmlWriter!S writeAttributes(XmlWriter!S aWriter)
    {
        assert(hasAttributes == true);

        auto attrb = firstAttribute;
        attrb.write(aWriter);

        attrb = attrb.nextSibling;
        while (attrb !is null)
        {
            aWriter.put(' ');
            attrb.write(aWriter);
            attrb = attrb.nextSibling;
        }

        return aWriter;
    }

    final XmlWriter!S writeChildren(XmlWriter!S aWriter)
    {
        assert(hasChildNodes == true);

        if (nodeType != XmlNodeType.document)
            aWriter.incNodeLevel();

        auto node = firstChild;
        while (node !is null)
        {
            node.write(aWriter);
            node = node.nextSibling;
        }        

        if (nodeType != XmlNodeType.document)
            aWriter.decNodeLevel();

        return aWriter;
    }

package:
    final XmlAttribute!S appendAttribute(XmlAttribute!S newAttribute)
    {
        if (!allowAttribute())
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "appendAttribute()");

        checkAttribute(newAttribute);

        if (!isLoading())
        {
            if (auto n = newAttribute.parentNode)
                n.removeAttribute(newAttribute);
        }

        newAttribute._parent = this;
        dlinkInsertEnd(_attrbLast, newAttribute);

        debug (Xml)
        {
            ++attrbVersion;
        }

        return newAttribute;
    }

    static bool getElementFilter(ref XmlNodeList!S aList, XmlNode!S aNode)
    {
        return (aNode.nodeType == XmlNodeType.element);
    }

    static bool getElementsByTagNameFilterName(ref XmlNodeList!S aList, XmlNode!S aNode)
    {
        if (aNode.nodeType != XmlNodeType.element)
            return false; 
        else
        {
            // Wildcar is already checked by caller
            auto context = cast(NameFilterContext!S) aList.context;
            return context.equalName(context.name, aNode.name);
        }
    }

    static bool getElementsByTagNameFilterUri(ref XmlNodeList!S aList, XmlNode!S aNode)
    {
        if (aNode.nodeType != XmlNodeType.element)
            return false; 
        else
        {
            auto context = cast(NameFilterContext!S) aList.context;
            return ((context.localName == "*" ||
                     context.equalName(context.localName, aNode.localName)) &&
                    context.equalName(context.namespaceUri, aNode.namespaceUri));
        }
    }

public:
    final XmlNodeList!S getAttributes()
    {
        return getAttributes(null);
    }

    final XmlNodeList!S getAttributes(Object aContext)
    {
        return XmlNodeList!S(this, XmlNodeListType.attributes, null, aContext);
    }

    final XmlNodeList!S getChildNodes()
    {
        return getChildNodes(null, No.deep);
    }

    final XmlNodeList!S getChildNodes(Object aContext, Flag!"deep" aDeep)
    {
        if (aDeep)
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, null, aContext);
        else
            return XmlNodeList!S(this, XmlNodeListType.childNodes, null, aContext);
    }

    final XmlNodeList!S getElements()
    {
        return getElements(null, No.deep);
    }

    final XmlNodeList!S getElements(Object aContext, Flag!"deep" aDeep)
    {
        if (aDeep)
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, &getElementFilter, aContext);
        else
            return XmlNodeList!S(this, XmlNodeListType.childNodes, &getElementFilter, aContext);
    }

    final XmlNodeList!S getElementsByTagName(S aName)
    {
        if (aName == "*")
            return getElements(null, Yes.deep);
        else
        {
            auto filterContext = new NameFilterContext!S(document, aName);
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, &getElementsByTagNameFilterName, filterContext);
        }
    }

    final XmlNodeList!S getElementsByTagName(S aLocalName, S aNamespaceUri)
    {
        auto filterContext = new NameFilterContext!S(document, aLocalName, aNamespaceUri);
        return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, &getElementsByTagNameFilterUri, filterContext);
    }

    version (none)
    XmlNodeList!S opSlice()
    {
        return children(false);
    }

public:
    version (none)  ~this()
    {
        removeAll();
        _ownerDocument = null;
    }

    final bool isAncestorNode(XmlNode!S aNode)
    {
        auto n = parentNode;
        while (n !is null && n !is this)
        {
            if (n is aNode)
                return true;
            n = n.parentNode;
        }

        return false;
    }

    bool allowAttribute() const
    {
        return false;
    }

    bool allowChild() const
    {
        return false;
    }

    bool allowChildType(XmlNodeType aNodeType)
    {
        return false;
    }

    final XmlAttribute!S appendAttribute(S aName)
    {
        XmlAttribute!S a = findAttribute(aName);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute(aName));

        return a;
    }

    final XmlNode!S appendChild(XmlNode!S newChild)
    {
        checkChild(newChild, "appendChild()");

        if (auto n = newChild.parentNode)
            n.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S next;
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            while (node !is null)
            {
                next = node.nextSibling;
                appendChild(newChild.removeChild(node));
                node = next;
            }
            return first;
        }

        newChild._parent = this;
        dlinkInsertEnd(_childLast, newChild);

        debug (Xml)
        {
            ++childVersion;
        }

        return newChild;
    }

    final XmlAttribute!S findAttribute(S aName)
    {
        const equalName = document.equalName;
        for (auto i = firstAttribute; i !is null; i = i.nextSibling)
        {
            if (equalName(i.name, aName))
                return cast(XmlAttribute!S) i;
        }
        return null;
    }

    final XmlAttribute!S findAttribute(S aLocalName, S aNamespaceUri)
    {
        const equalName = document.equalName;
        for (auto i = firstAttribute; i !is null; i = i.nextSibling)
        {
            if (equalName(i.localName, aLocalName) && equalName(i.namespaceUri, aNamespaceUri))
                return cast(XmlAttribute!S) i;
        }
        return null;
    }

    final XmlAttribute!S findAttributeById()
    {
        for (auto i = firstAttribute; i !is null; i = i.nextSibling)
        {
            if (equalCaseInsensitive!S(i.name, "id"))
                return cast(XmlAttribute!S) i;
        }
        return null;
    }

    final XmlElement!S findElement(S aName)
    {
        const equalName = document.equalName;
        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element && equalName(i.name, aName))
                return cast(XmlElement!S) i;
        }
        return null;
    }

    final XmlElement!S findElement(S aLocalName, S aNamespaceUri)
    {
        const equalName = document.equalName;
        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element && 
                equalName(i.localName, aLocalName) && 
                equalName(i.namespaceUri, aNamespaceUri))
                return cast(XmlElement!S) i;
        }
        return null;
    }

    final S getAttribute(S aName)
    {
        auto a = findAttribute(aName);
        if (a is null)
            return null;
        else
            return a.value;
    }

    final S getAttribute(S aLocalName, S aNamespaceUri)
    {
        auto a = findAttribute(aLocalName, aNamespaceUri);
        if (a is null)
            return null;
        else
            return a.value;
    }

    final S getAttributeById()
    {
        auto a = findAttributeById();
        if (a is null)
            return null;
        else
            return a.value;
    }

    final XmlElement!S getElementById(S aId)
    {
        XmlElement!S result;
        getElementById(this, aId, result);
        return result;
    }

    final XmlElement!S opIndex(S aName)
    {
        return findElement(aName);
    }

    final XmlElement!S opIndex(S aLocalName, S aNamespaceUri)
    {
        return findElement(aLocalName, aNamespaceUri);
    }

    final XmlNode!S insertChildAfter(XmlNode!S newChild, XmlNode!S refChild)
    {
        checkChild(newChild, "insertChildAfter()");

        if (refChild is null)
            return appendChild(newChild);

        checkParent(refChild, true, "insertChildAfter()");

        if (auto n = newChild.parentNode)
            n.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S next;
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            while (node !is null)
            {
                next = node.nextSibling;
                insertChildAfter(newChild.removeChild(node), refChild);
                refChild = node;
                node = next;
            }
            return first;
        }

        newChild._parent = this;
        dlinkInsertAfter(refChild, newChild);

        debug (Xml)
        {
            ++childVersion;
        }

        return newChild;
    }

    final XmlNode!S insertChildBefore(XmlNode!S newChild, XmlNode!S refChild)
    {
        checkChild(newChild, "insertChildBefore()");

        if (refChild is null)
            return appendChild(newChild);

        checkParent(refChild, true, "insertChildBefore()");

        if (auto n = newChild.parentNode)
            n.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            if (node !is null)
            {
                insertChildBefore(newChild.removeChild(node), refChild);
                // insert the rest of the children after this one.
                insertChildAfter(newChild, node);
            }
            return first;
        }

        newChild._parent = this;
        dlinkInsertAfter(refChild._prev, newChild);

        debug (Xml)
        {
            ++childVersion;
        }

        return newChild;
    }

    final S outerXml(Flag!"PrettyOutput" aPrettyOutput = No.PrettyOutput)
    {
        auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
        write(new XmlStringWriter!S(aPrettyOutput, buffer));
        return selfOwnerDocument.getAndReleaseBuffer(buffer);
    }

    final void removeAll()
    {
        removeChildNodes();
        removeAttributes();
    }

    final XmlAttribute!S removeAttribute(XmlAttribute!S oldAttribute)
    {
        checkParent(oldAttribute, false, "removeAttribute()");

        oldAttribute._parent = null;
        dlinkRemove(_attrbLast, oldAttribute);

        debug (Xml)
        {
            ++attrbVersion;
        }

        return oldAttribute;
    }

    final XmlAttribute!S removeAttribute(S aName)
    {
        XmlAttribute!S r = findAttribute(aName);
        if (r is null)
            return null;
        else
            return removeAttribute(r);
    }

    void removeAttributes()
    {
        if (_attrbLast !is null)
        {
            while (_attrbLast !is null)
            {
                _attrbLast._parent = null;
                dlinkRemove(_attrbLast, _attrbLast);
            }

            debug (Xml)
            {
                ++attrbVersion;
            }
        }
    }

    void removeChildNodes()
    {
        if (_childLast !is null)
        {
            while (_childLast !is null)
            {
                _childLast._parent = null;
                dlinkRemove(_childLast, _childLast);
            }

            debug (Xml)
            {
                ++childVersion;
            }
        }
    }

    final XmlNode!S removeChild(XmlNode!S oldChild)
    {
        checkParent(oldChild, true, "removeChild()");

        oldChild._parent = null;
        dlinkRemove(_childLast, oldChild);

        debug (Xml)
        {
            ++childVersion;
        }

        return oldChild;
    }

    final XmlNode!S replaceChild(XmlNode!S newChild, XmlNode!S oldChild)
    {
        checkChild(newChild, "replaceChild()");
        checkParent(oldChild, true, "replaceChild()");

        XmlNode!S pre = oldChild.previousSibling;

        oldChild._parent = null;
        dlinkRemove(_childLast, oldChild);

        insertChildAfter(newChild, pre);

        return oldChild;
    }

    final XmlAttribute!S setAttribute(S aName, S aText)
    {
        if (!allowAttribute())
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "setAttribute()");

        XmlAttribute!S a = findAttribute(aName);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute(aName));
        a.value = aText;
        return a;
    }

    final XmlAttribute!S setAttribute(S aLocalName, S aNamespaceUri, S aText)
    {
        if (!allowAttribute())
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "setAttribute()");

        XmlAttribute!S a = findAttribute(aLocalName, aNamespaceUri);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute("", aLocalName, aNamespaceUri));
        a.value = aText;
        return a;
    }

    abstract XmlWriter!S write(XmlWriter!S aWriter);

@property:
    XmlNodeList!S attributes()
    {
        return getAttributes(null);
    }

    XmlNodeList!S childNodes()
    {
        return getChildNodes(null, No.deep);
    }

    XmlDocument!S document()
    {
        XmlDocument!S d;

        if (_parent !is null)
        {
            if (_parent.nodeType == XmlNodeType.document)
                return cast(XmlDocument!S) _parent;
            else
                d = _parent.document;
        }

        if (d is null)
        {
            d = ownerDocument;
            if (d is null)
                return selfOwnerDocument;
        }

        return d;
    }

    final XmlNode!S firstAttribute()
    {
        if (_attrbLast is null)
            return null;
        else
            return _attrbLast._next;
    }

    final XmlNode!S firstChild()
    {
        if (_childLast is null)
            return null;
        else
            return _childLast._next;
    }

    final bool hasAttributes()
    {
        return (_attrbLast !is null);
    }

    final bool hasChildNodes()
    {
        return (_childLast !is null);
    }

    final bool hasValue(Flag!"checkContent" checkContent)
    {
        switch (nodeType)
        {
            case XmlNodeType.attribute:
            case XmlNodeType.cDataSection:
            case XmlNodeType.comment:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.text:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.whitespace:
            case XmlNodeType.declaration:
                return (!checkContent || value.length > 0);
            default:
                return false;
        }
    }

    S innerText()
    {
        auto first = firstChild;
        if (first is null)
            return null;
        else if (isOnlyNode(first) && first.isText)
            return first.innerText;
        else
        {
            auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
            appendChildText(new XmlStringWriter!S(No.PrettyOutput, buffer));
            return selfOwnerDocument.getAndReleaseBuffer(buffer);
        }
    }

    S innerText(S newValue)
    {
        auto first = firstChild;
        if (isOnlyNode(first) && first.nodeType == XmlNodeType.text)
            first.innerText = newValue;
        else
        {
            removeChildNodes();
            appendChild(selfOwnerDocument.createText(newValue));
        }
        return newValue;
    }

    final bool isNamespaceNode()
    {
        return (nodeType == XmlNodeType.attribute &&                
                localName.length > 0 &&                
                value.length > 0 &&
                document.equalName(prefix, XmlConst.xmlns));
    }

    final bool isOnlyNode(XmlNode!S aNode) const
    {
        return (aNode !is null && 
                aNode.previousSibling is null &&
                aNode.nextSibling is null);
    }

    final XmlNode!S lastAttribute()
    {
        return _attrbLast;
    }

    final XmlNode!S lastChild()
    {
        return _childLast;
    }

    size_t level()
    {
        if (parentNode is null)
            return 0;
        else
            return parentNode.level + 1;
    }

    final S localName()
    {
        return _qualifiedName.localName;
    }

    final S name()
    {
        return _qualifiedName.name;
    }

    final S namespaceUri()
    {
        return _qualifiedName.namespaceUri;
    }

    final XmlNode!S nextSibling()
    {
        if (parentNode is null)
            return _next;

        XmlNode!S last;
        if (nodeType == XmlNodeType.attribute)
            last = parentNode.lastAttribute;
        else
            last = parentNode.lastChild;

        if (this is last)
            return null;
        else
            return _next;
    }

    abstract XmlNodeType nodeType() const;

    final XmlDocument!S ownerDocument()
    {
        return _ownerDocument;
    }

    final XmlNode!S parentNode()
    {
        return _parent;
    }

    /// Based 1 value
    final ptrdiff_t position()
    {
        if (auto p = parentNode())
        {
            ptrdiff_t result = 1;
            if (nodeType == XmlNodeType.attribute)
            {
                auto e = p.firstAttribute;
                while (e !is null)
                {
                    if (e is this)
                        return result;
                    ++result;
                    e = e.nextSibling;
                }
            }
            else
            {
                auto e = p.firstChild;
                while (e !is null)
                {
                    if (e is this)
                        return result;
                    ++result;
                    e = e.nextSibling;
                }
            }
        }

        return -1;
    }

    final S prefix()
    {
        return _qualifiedName.prefix;
    }

    S prefix(S newValue)
    {
        throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "prefix()");
    }

    final XmlNode!S previousSibling()
    {
        if (parentNode is null)
            return _prev;

        XmlNode!S first;
        if (nodeType == XmlNodeType.attribute)
            first = parentNode.firstAttribute;
        else
            first = parentNode.firstChild;

        if (this is first)
            return null;
        else
            return _prev;
    }

    S value()
    {
        return null;
    }

    S value(S newValue)
    {
        throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "value()");
    }
}

enum XmlNodeListType
{
    attributes,
    childNodes,
    childNodesDeep,
    flat
}

struct XmlNodeList(S)
if (isXmlString!S)
{
public:
    alias XmlNodeListFilterEvent = bool function(ref XmlNodeList!S aList, XmlNode!S aNode);

private:
    struct WalkNode
    {
        XmlNode!S parent, next;
        debug (Xml) size_t parentVersion;

        this(XmlNode!S aParent, XmlNode!S aNext)
        {
            parent = aParent;
            next = aNext;
            debug (Xml)
                parentVersion = aParent.childVersion;
        }
    }

    Object _context;
    XmlNode!S _orgParent, _parent, _current;
    XmlNode!S[] _flatList;
    WalkNode[] _walkNodes;
    XmlNodeListFilterEvent _onFilter;
    size_t _currentIndex;
    size_t _length = size_t.max;
    int _inFilter;
    XmlNodeListType _listType;
    bool _emptyList;

    debug (Xml)
    {
        size_t _parentVersion;

        pragma(inline, true)
        size_t getVersionAttrb()
        {
            return _parent.attrbVersion;
        }

        pragma(inline, true)
        size_t getVersionChild()
        {
            return _parent.childVersion;
        }

        void checkVersionChangedAttrb()
        {
            if (_parentVersion != getVersionAttrb())
                throw new XmlException(Message.EAttributeListChanged);
        }

        void checkVersionChangedChild()
        {
            if (_parentVersion != getVersionChild())
                throw new XmlException(Message.EChildListChanged);
        }

        pragma(inline, true)
        void checkVersionChanged()
        {
            if (_listType == XmlNodeListType.Attributes)
                checkVersionChangedAttrb();
            else
                checkVersionChangedChild();
        }
    }

    void checkFilter(void delegate() aAdvance)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.checkFilter()");

        assert(_listType != XmlNodeListType.flat);

        ++_inFilter;
        scope (exit)
            --_inFilter;

        while (_current !is null && !_onFilter(this, _current))
            aAdvance();
    }

    void popFrontSibling()
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.popFrontSibling()");

        assert(_listType != XmlNodeListType.flat);
        assert(_current !is null);

        _current = _current.nextSibling;

        if (_inFilter == 0 && _onFilter !is null)
            checkFilter(&popFrontSibling);
    }

    void popFrontDeep()
    {
        version (none)
        version (unittest)
        outputXmlTraceParserF("XmlNodeList.popFrontDeep(current(%s.%s))", _parent.name, _current.name);

        assert(_listType != XmlNodeListType.flat);
        assert(_current !is null);

        if (_current.hasChildNodes)
        {
            if (_current.nextSibling !is null)
            {
                version (none)
                version (unittest)
                outputXmlTraceParserF("XmlNodeList.popFrontDeep(push(%s.%s))", _parent.name,
                    _current.nextSibling.name);

                _walkNodes ~= WalkNode(_parent, _current.nextSibling);
            }

            _parent = _current;
            _current = _current.firstChild;
            debug (Xml)
                _parentVersion = getVersionChild();
        }
        else
        {
            _current = _current.nextSibling;
            while (_current is null && _walkNodes.length > 0)
            {
                size_t index = _walkNodes.length - 1;
                _parent = _walkNodes[index].parent;
                _current = _walkNodes[index].next;
                debug (Xml)
                    _parentVersion = _walkNodes[index].parentVersion;

                _walkNodes.length = index;
            }
        }

        if (_inFilter == 0 && _onFilter !is null)
            checkFilter(&popFrontDeep);
    }

    XmlNode!S getItemSibling(size_t aIndex)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.getItem()");

        assert(_listType != XmlNodeListType.flat);

        if (_current is null || aIndex == 0)
            return _current;

        auto restore = this;

        while (aIndex > 0 && _current !is null)
        {
            popFrontSibling();
            --aIndex;
        }

        auto result = _current;
        this = restore;

        if (aIndex == 0)
            return result;
        else
            return null;
    }

    XmlNode!S getItemDeep(size_t aIndex)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.getItemDeep()");

        assert(_listType != XmlNodeListType.flat);

        if (_current is null || aIndex == 0)
            return _current;

        auto restore = this;

        while (aIndex > 0 && _current !is null)
        {
            popFrontDeep();
            --aIndex;
        }

        auto result = _current;
        this = restore;

        if (aIndex == 0)
            return result;
        else
            return null;
    }

    version(none)
    void moveBackSibling()
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.moveBackSibling()");

        assert(_listType != XmlNodeListType.flat);
        assert(_current !is null);

        _current = _current.previousSibling;

        if (_inFilter == 0 && _onFilter !is null)
            checkFilter(&moveBackSibling);
    }

public:
    this(this)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.this(this)");

        if (_listType == XmlNodeListType.childNodesDeep)
            _walkNodes = _walkNodes.dup;
    }

    this(XmlNode!S aParent, XmlNodeListType aListType, XmlNodeListFilterEvent aOnFilter, Object aContext)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.this(...)");

        if (aListType == XmlNodeListType.flat)
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate,
                "XmlNodeList", "this(listType = XmlNodeListType.flat)");

        _orgParent = aParent;
        _listType = aListType;
        _onFilter = aOnFilter;
        _context = aContext;

        if (_listType == XmlNodeListType.childNodesDeep)
            _walkNodes.reserve(defaultXmlLevels);

        reset();
    }

    this(Object aContext)
    {
        _context = aContext;
        _listType = XmlNodeListType.flat;
    }

    XmlNode!S insertBack(XmlNode!S aNode)
    {
        if (_listType != XmlNodeListType.flat)
            throw new XmlInvalidOperationException(Message.eInvalidOpDelegate,
                    "XmlNodeList", "insertBack(listType != XmlNodeListType.flat)");

        _flatList ~= aNode;
        return aNode;
    }

    XmlNode!S item(size_t aIndex)
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.item()");

        if (_listType == XmlNodeListType.flat)
        {
            size_t i = aIndex + _currentIndex;
            if (i < _flatList.length)
                return _flatList[i];
            else
                return null;
        }
        else
        {
            debug (Xml)
                checkVersionChanged();

            if (empty)
                return null;

            if (_listType == XmlNodeListType.childNodesDeep)
                return getItemDeep(aIndex);
            else
                return getItemSibling(aIndex);
        }
    }

    XmlNode!S moveFront()
    {
        XmlNode!S f = front;
        popFront();
        return f;
    }

    void popFront()
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.popFront()");

        if (_listType == XmlNodeListType.flat)
            ++_currentIndex;
        else
        {
            debug (Xml)
                checkVersionChanged();

            if (_listType == XmlNodeListType.childNodesDeep)
                popFrontDeep();
            else
                popFrontSibling();
            _length = size_t.max;
        }
    }

    /// Based 1 value
    ptrdiff_t position(XmlNode!S aNode)
    {
        for (size_t i = 0; i < length; ++i)
        {
            if (aNode is item(i))
                return (i + 1);
        }

        return -1;
    }

    void removeAll()
    {
        final switch (_listType)
        {
            case XmlNodeListType.attributes:
                _orgParent.removeAttributes();
                break;
            case XmlNodeListType.childNodes:
            case XmlNodeListType.childNodesDeep:
                _orgParent.removeChildNodes();
                break;
            case XmlNodeListType.flat:
                _flatList.length = 0;
                break;
        }

        reset();
    }

    void reset()
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.reset()");

        if (_listType == XmlNodeListType.flat)
            _currentIndex = 0;
        else
        {
            _parent = _orgParent;
            switch (_listType)
            {
                case XmlNodeListType.attributes:
                    _current = _parent.firstAttribute;
                    break;
                case XmlNodeListType.childNodes:
                case XmlNodeListType.childNodesDeep:
                    _current = _parent.firstChild;
                    break;
                default:
                    assert(0);
            }

            debug (Xml)
            {
                if (_listType == XmlNodeListType.Attributes)
                    _parentVersion = getVersionAttrb();
                else
                    _parentVersion = getVersionChild();
            }

            if (_onFilter !is null)
                checkFilter(&popFront);

            _emptyList = _current is null;
            if (empty)
                _length = 0;
            else
                _length = size_t.max;
        }
    }

@property:
    XmlNode!S back()
    {
        if (_listType == XmlNodeListType.flat)
            return _flatList[$ - 1];
        else
            return item(length() - 1);
    }

    Object context()
    {
        return _context;
    }

    bool empty()
    {
        if (_listType == XmlNodeListType.flat)
            return (_currentIndex >= _flatList.length);
        else
            return (_current is null || _emptyList);
    }

    XmlNode!S front()
    {
        if (_listType == XmlNodeListType.flat)
            return _flatList[_currentIndex];
        else
            return _current;
    }

    size_t length()
    {
        version (none)
        version (unittest)
        outputXmlTraceParser("XmlNodeList.length()");

        if (empty)
            return 0;

        if (_listType == XmlNodeListType.flat)
            return _flatList.length - _currentIndex;
        else
        {
            debug (Xml)
                checkVersionChanged();

            if (_length == size_t.max)
            {
                size_t tempLength;
                auto restore = this;

                while (_current !is null)
                {
                    ++tempLength;
                    popFront();
                }

                this = restore;
                _length = tempLength;
            }

            return _length;
        }
    }

    XmlNode!S parent()
    {
        return _orgParent;
    }

    auto save()
    {
        return this;
    }
}

class XmlAttribute(S) : XmlNode!S
{
protected:
    XmlString!S _text;

package:
    this(XmlDocument!S aOwnerDocument, XmlName!S aName, XmlString!S aText)
    {
        if (!aOwnerDocument.isLoading())
        {
            checkName!(S, Yes.allowEmpty)(aName.prefix);
            checkName!(S, No.allowEmpty)(aName.localName);
        }

        super(aOwnerDocument);
        _qualifiedName = aName;
        _text = aText;
    }

public:
    this(XmlDocument!S aOwnerDocument, XmlName!S aName)
    {
        if (!aOwnerDocument.isLoading())
        {
            checkName!(S, Yes.allowEmpty)(aName.prefix);
            checkName!(S, No.allowEmpty)(aName.localName);
        }

        super(aOwnerDocument);
        _qualifiedName = aName;
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putAttribute(name, ownerDocument.getEncodeText(_text));
        return aWriter;
    }

@property:
    final override S innerText()
    {
        return value;
    }

    final override S innerText(S newValue)
    {
        return value(newValue);
    }

    final override size_t level()
    {
        if (parentNode is null)
            return 0;
        else
            return parentNode.level;
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.attribute;
    }

    final override S prefix(S newValue)
    {
        _qualifiedName = ownerDocument.createName(newValue, localName, namespaceUri);
        return newValue;
    }

    final override S value()
    {
        return ownerDocument.getDecodeText(_text);
    }

    final override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlCDataSection(S) : XmlCharacterData!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.cDataSectionTagName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aData)
    {
        super(aOwnerDocument, XmlString!S(aData, XmlEncodeMode.none));
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putCDataSection(_text.value);
        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.cDataSection;
    }
}

class XmlComment(S) : XmlCharacterData!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.commentTagName);
    }

package:
    this(XmlDocument!S aOwnerDocument, XmlString!S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putComment(ownerDocument.getEncodeText(_text));
        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.comment;
    }
}

class XmlDeclaration(S) : XmlNode!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.declarationTagName);
    }

protected:
    S _innerText;

    final void breakText(S s)
    {
        import std.array : split;

        S[] t = s.split();
        foreach (e; t)
        {
            S name, value;
            splitNameValueD(e, '=', name, value);

            const equalName = document.equalName;
            if (equalName(name, XmlConst.declarationVersionName))
                versionStr = value;
            else if (equalName(name, XmlConst.declarationEncodingName))
                encoding = value;
            else if (equalName(name, XmlConst.declarationStandaloneName))
                standalone = value;
            else
                throw new XmlException(Message.eInvalidName, name);
        }
    }

    final S buildText()
    {
        if (_innerText.length == 0)
        {
            auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
            auto writer = new XmlStringWriter!S(No.PrettyOutput, buffer);

            S s;

            writer.putAttribute(XmlConst.declarationVersionName, versionStr);

            s = encoding;
            if (s.length > 0)
            {
                writer.put(' ');
                writer.putAttribute(XmlConst.declarationEncodingName, s);
            }

            s = standalone;
            if (s.length > 0)
            {
                writer.put(' ');
                writer.putAttribute(XmlConst.declarationStandaloneName, s);
            }

            _innerText = buffer.toString();
            selfOwnerDocument.releaseBuffer(buffer);
        }

        return _innerText;
    }

    final void checkStandalone(S s)
    {
        if ((s.length > 0) && (s != XmlConst.yes || s != XmlConst.no))
            throw new XmlException(Message.eInvalidTypeValueOf2,
                    XmlConst.declarationStandaloneName, XmlConst.yes, XmlConst.no, s);
    }

    final void checkVersion(S s) // rule 26
    {
        if (!isVersionStr!(S, Yes.allowEmpty)(s))
            throw new XmlException(Message.eInvalidVersionStr, s);
    }

public:
    this(XmlDocument!S aOwnerDocument)
    {
        super(aOwnerDocument);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    this(XmlDocument!S aOwnerDocument, S aVersionStr, S aEncoding, S aStandalone)
    {
        checkStandalone(aStandalone);
        checkVersion(aVersionStr);

        this(aOwnerDocument);
        versionStr = aVersionStr;
        encoding = aEncoding;
        standalone = aStandalone;
    }

    final override bool allowAttribute() const
    {
        return true;
    }

    final void setDefaults()
    {
        if (versionStr.length == 0)
            versionStr = "1.0";
        if (encoding.length == 0)
            encoding = "utf-8";
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        Flag!"hasAttribute" a;
        if (hasAttributes)
            a = Yes.hasAttribute;

        aWriter.putElementNameBegin("?xml", a);
        if (a)
            writeAttributes(aWriter);
        aWriter.putElementNameEnd("?xml", No.hasChild);
        return aWriter;
    }

@property:
    final S encoding()
    {
        return getAttribute(XmlConst.declarationEncodingName);
    }

    final void encoding(S newValue)
    {
        _innerText = null;
        if (newValue.length == 0)
            removeAttribute(XmlConst.declarationEncodingName);
        else
            setAttribute(XmlConst.declarationEncodingName, newValue);
    }

    final override S innerText()
    {
        return buildText();
    }

    final override S innerText(S newValue)
    {
        breakText(newValue);
        return newValue;
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.declaration;
    }

    final S standalone()
    {
        return getAttribute(XmlConst.declarationStandaloneName);
    }

    final S standalone(S newValue)
    {
        checkStandalone(newValue);

        _innerText = null;
        if (newValue.length == 0)
            removeAttribute(XmlConst.declarationStandaloneName);
        else
            setAttribute(XmlConst.declarationStandaloneName, newValue);
        return newValue;
    }

    final override S value()
    {
        return buildText();
    }

    final override S value(S newValue)
    {
        breakText(newValue);
        return newValue;
    }

    final S versionStr()
    {
        return getAttribute(XmlConst.declarationVersionName);
    }

    final S versionStr(S newValue)
    {
        _innerText = null;
        if (newValue.length == 0)
            removeAttribute(XmlConst.declarationVersionName);
        else
            setAttribute(XmlConst.declarationVersionName, newValue);
        return newValue;
    }
}

class XmlDocument(S) : XmlNode!S
{
public:
    alias EqualName = bool function(const(C)[] s1, const(C)[] s2);

protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.documentTagName);
    }

protected:
    XmlBufferList!(S, No.checkEncoded) _buffers;
    XmlEntityTable!S _entityTable;
    S[S] _symbolTable;
    int _loading;

    pragma(inline, true)
    final XmlBuffer!(S, No.checkEncoded) acquireBuffer(XmlNodeType fromNodeType, size_t aCapacity = 0)
    {
        auto b = _buffers.acquire();
        if (aCapacity == 0 && fromNodeType == XmlNodeType.document)
            aCapacity = 64000;
        if (aCapacity != 0)
            b.capacity = aCapacity;

        return b;
    }

    pragma(inline, true)
    final S getAndReleaseBuffer(XmlBuffer!(S, No.checkEncoded) b)
    {
        return _buffers.getAndRelease(b);
    }

    final S getDecodeText(ref XmlString!S s)
    {
        if (s.needDecode())
        {
            auto buffer = acquireBuffer(XmlNodeType.text, s.length);
            auto result = s.decodeText(buffer, decodeEntityTable());
            releaseBuffer(buffer);
            return result;
        }
        else
            return s.toString();
    }

    final S getEncodeText(ref XmlString!S s)
    {
        if (s.needEncode())
        {
            auto buffer = acquireBuffer(XmlNodeType.text, s.length);
            auto result = s.encodeText(buffer);
            releaseBuffer(buffer);
            return result;
        }
        else
            return s.toString();
    }

    pragma(inline, true)
    final void releaseBuffer(XmlBuffer!(S, No.checkEncoded) b)
    {
        _buffers.release(b);
    }

    final override bool isLoading()
    {
        return _loading != 0;
    }

    final override XmlDocument!S selfOwnerDocument()
    {
        return this;
    }

package:
    final S addSymbol(S n)
    {
        auto e = n in _symbolTable;
        if (e is null)
        {
            _symbolTable[n] = n;
            e = n in _symbolTable;
        }
        return *e;
    }

    pragma(inline, true)
    final S addSymbolIf(S n)
    {
        if (n.length == 0 || !parseOptions.useSymbolTable)
            return n;
        else
            return addSymbol(n);
    }

    pragma(inline, true)
    final XmlName!S createName(S aQualifiedName)
    {
        return new XmlName!S(this, aQualifiedName);
    }

    pragma(inline, true)
    final XmlName!S createName(S aPrefix, S aLocalName, S aNamespaceUri)
    {
        return new XmlName!S(this, aPrefix, aLocalName, aNamespaceUri);
    }

    final const(XmlEntityTable!S) decodeEntityTable()
    {
        if (_entityTable is null)
            return XmlEntityTable!S.defaultEntityTable();
        else
            return _entityTable;
    }

package:
    XmlDocumentTypeAttributeListDef!S createAttributeListDef(XmlDocumentTypeAttributeListDefType!S aDefType,
        S aDefaultType, XmlString!S aDefaultText)
    {
        return new XmlDocumentTypeAttributeListDef!S(this, aDefType, aDefaultType, aDefaultText);
    }

    XmlDocumentTypeAttributeListDefType!S createAttributeListDefType(S aName, S aType, S[] aTypeItems)
    {
        return new XmlDocumentTypeAttributeListDefType!S(this, aName, aType, aTypeItems);
    }

    XmlAttribute!S createAttribute(S aName, XmlString!S aText)
    {
        return new XmlAttribute!S(this, createName(aName), aText);
    }

    XmlComment!S createComment(XmlString!S aText)
    {
        return new XmlComment!S(this, aText);
    }

    XmlDocumentType!S createDocumentType(S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText)
    {
        return new XmlDocumentType!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlEntity!S createEntity(S aName, XmlString!S aText)
    {
        return new XmlEntity!S(this, aName, aText);
    }

    XmlEntity!S createEntity(S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText, S aNotationName)
    {
        return new XmlEntity!S(this, aName, aPublicOrSystem, aPublicId, aText, aNotationName);
    }

    XmlEntityReference!S createEntityReference(S aName, XmlString!S aText)
    {
        return new XmlEntityReference!S(this, aName, aText);
    }

    XmlEntityReference!S createEntityReference(S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText)
    {
        return new XmlEntityReference!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlNotation!S createNotation(S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText)
    {
        return new XmlNotation!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlProcessingInstruction!S createProcessingInstruction(S aTarget, XmlString!S aText)
    {
        return new XmlProcessingInstruction!S(this, aTarget, aText);
    }

    XmlText!S createText(XmlString!S aText)
    {
        return new XmlText!S(this, aText);
    }

public:
    S defaultUri;
    XmlParseOptions!S parseOptions;
    EqualName equalName;

    this()
    {
        super(null);
        equalName = &equalCase!S;
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
        _buffers = new XmlBufferList!(S, No.checkEncoded)();
    }

    final override bool allowChild() const
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType aNodeType)
    {
        switch (aNodeType)
        {
            case XmlNodeType.comment:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.whitespace:
                return true;
            case XmlNodeType.declaration:
                return documentDeclaration is null;
            case XmlNodeType.documentType:
                return documentType is null;
            case XmlNodeType.element:
                return documentElement is null;
            default:
                return false;
        }
    }

    final XmlDocument!S load(S aXmlText)
    {
        auto reader = new XmlStringReader!S(aXmlText);
        return load(reader);
    }

    final XmlDocument!S load(XmlReader!S aReader)
    {
        ++_loading;
        scope (exit)
            --_loading;

        removeAll();

        auto parser = XmlParser!S(this, aReader);
        return parser.parse();
    }

    final XmlDocument!S loadFromFile(string aFileName)
    {
        auto reader = new XmlFileReader!S(aFileName);
        scope (exit)
            reader.close();

        return load(reader);
    }

    final string saveToFile(string aFileName, Flag!"PrettyOutput" aPrettyOutput = No.PrettyOutput)
    {
        auto writer = new XmlFileWriter!S(aFileName, aPrettyOutput);
        scope (exit)
            writer.close();

        write(writer);
        return aFileName;
    }

    XmlAttribute!S createAttribute(S aName)
    {
        return new XmlAttribute!S(this, createName(aName));
    }

    XmlAttribute!S createAttribute(S aName, S aValue)
    {
        auto a = createAttribute(aName);
        a.value = aValue;
        return a;
    }

    XmlAttribute!S createAttribute(S aPrefix, S aLocalName, S aNamespaceUri)
    {
        return new XmlAttribute!S(this, createName(aPrefix, aLocalName, aNamespaceUri));
    }

    XmlCDataSection!S createCDataSection(S aData)
    {
        return new XmlCDataSection!S(this, aData);
    }

    XmlComment!S createComment(S aText)
    {
        return new XmlComment!S(this, aText);
    }

    XmlDeclaration!S createDeclaration()
    {
        return new XmlDeclaration!S(this);
    }

    XmlDeclaration!S createDeclaration(S aVersionStr, S aEncoding, S aStandalone)
    {
        return new XmlDeclaration!S(this, aVersionStr, aEncoding, aStandalone);
    }

    XmlDocumentType!S createDocumentType(S aName)
    {
        return new XmlDocumentType!S(this, aName);
    }

    XmlDocumentType!S createDocumentType(S aName, S aPublicOrSystem, S aPublicId, S aText)
    {
        return new XmlDocumentType!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlDocumentTypeAttributeList!S createDocumentTypeAttributeList(S aName)
    {
        return new XmlDocumentTypeAttributeList!S(this, aName);
    }

    XmlDocumentTypeElement!S createDocumentTypeElement(S aName)
    {
        return new XmlDocumentTypeElement!S(this, aName);
    }

    XmlElement!S createElement(S aName)
    {
        return new XmlElement!S(this, createName(aName));
    }

    XmlElement!S createElement(S aPrefix, S aLocalName, S aNamespaceUri)
    {
        return new XmlElement!S(this, createName(aPrefix, aLocalName, aNamespaceUri));
    }

    XmlEntity!S createEntity(S aName, S aValue)
    {
        return new XmlEntity!S(this, aName, aValue);
    }

    XmlEntity!S createEntity(S aName, S aPublicOrSystem, S aPublicId, S aText, S aNotationName)
    {
        return new XmlEntity!S(this, aName, aPublicOrSystem, aPublicId, aText, aNotationName);
    }

    XmlEntityReference!S createEntityReference(S aName, S aText)
    {
        return new XmlEntityReference!S(this, aName, aText);
    }

    XmlEntityReference!S createEntityReference(S aName, S aPublicOrSystem, S aPublicId, S aText)
    {
        return new XmlEntityReference!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlNotation!S createNotation(S aName, S aPublicOrSystem, S aPublicId, S aText)
    {
        return new XmlNotation!S(this, aName, aPublicOrSystem, aPublicId, aText);
    }

    XmlProcessingInstruction!S createProcessingInstruction(S aTarget, S aText)
    {
        return new XmlProcessingInstruction!S(this, aTarget, aText);
    }

    XmlSignificantWhitespace!S createSignificantWhitespace(S aText)
    {
        return new XmlSignificantWhitespace!S(this, aText);
    }

    XmlText!S createText(S aText)
    {
        return new XmlText!S(this, aText);
    }

    XmlWhitespace!S createWhitespace(S aText)
    {
        return new XmlWhitespace!S(this, aText);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        if (hasChildNodes)
            writeChildren(aWriter);

        return aWriter;
    }

@property:
    final override XmlDocument!S document()
    {
        return this;
    }

    final XmlDeclaration!S documentDeclaration()
    {
        return cast(XmlDeclaration!S) findChild(XmlNodeType.declaration);
    }

    final XmlElement!S documentElement()
    {
        return cast(XmlElement!S) findChild(XmlNodeType.element);
    }

    final XmlDocumentType!S documentType()
    {
        return cast(XmlDocumentType!S) findChild(XmlNodeType.documentType);
    }

    final XmlEntityTable!S entityTable()
    {
        if (_entityTable is null)
            _entityTable = new XmlEntityTable!S();
        return _entityTable;
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.document;
    }
}

class XmlDocumentFragment(S) : XmlNode!S
{
protected:
    static shared XmlName!S qualifiedName;
    static XmlName!S createQualifiedName()
    {
        return new XmlName!S(null, XmlConst.documentFragmentTagName);
    }

public:
    final override bool allowChild() const
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType aNodeType)
    {
        switch (aNodeType)
        {
            case XmlNodeType.CDataSection:
            case XmlNodeType.Comment:
            case XmlNodeType.Element:
            case XmlNodeType.Entity:
            case XmlNodeType.EntityReference:
            case XmlNodeType.Notation:
            case XmlNodeType.ProcessingInstruction:
            case XmlNodeType.SignificantWhitespace:
            case XmlNodeType.Text:
            case XmlNodeType.Whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "write()");
        //todo
        //return writer;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.DocumentFragment;
    }

    final override XmlNode!S parentNode()
    {
        return null;
    }
}

class XmlDocumentType(S) : XmlNode!S
{
protected:
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;

public:
    this(XmlDocument!S aOwnerDocument, S aName)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aName);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, S aPublicId, S aText)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = XmlString!S(aPublicId);
        _text = XmlString!S(aText);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, XmlString!S aPublicId, XmlString!S aText)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = aPublicId;
        _text = aText;
    }

    final override bool allowChild() const
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType aNodeType)
    {
        switch (aNodeType)
        {
            case XmlNodeType.comment:
            case XmlNodeType.documentTypeAttributeList:
            case XmlNodeType.documentTypeElement:
            case XmlNodeType.entity:
            case XmlNodeType.entityReference:
            case XmlNodeType.notation:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.text:
            case XmlNodeType.whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        Flag!"hasChild" c;
        if (hasChildNodes)
            c = Yes.hasChild;

        aWriter.putDocumentTypeBegin(name, publicOrSystem,
            ownerDocument.getEncodeText(_publicId), ownerDocument.getEncodeText(_text), c);
        if (c)
            writeChildren(aWriter);
        aWriter.putDocumentTypeEnd(c);

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.documentType;
    }

    final S publicId()
    {
        return ownerDocument.getDecodeText(_publicId);
    }

    final S publicId(S newValue)
    {
        _publicId = newValue;
        return newValue;
    }

    final S publicOrSystem()
    {
        return _publicOrSystem;
    }

    final S publicOrSystem(S newValue)
    {
        const equalName = document.equalName;
        if (newValue.length == 0 ||
            equalName(newValue, XmlConst.public_) ||
            equalName(newValue, XmlConst.system))
            return _publicOrSystem = newValue;
        else
            return null;
    }

    final override S value()
    {
        return ownerDocument.getDecodeText(_text);
    }

    final override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlDocumentTypeAttributeList(S) : XmlNode!S
{
protected:
    XmlDocumentTypeAttributeListDef!S[] _defs;

public:
    this(XmlDocument!S aOwnerDocument, S aName)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aName);
    }

    final void appendDef(XmlDocumentTypeAttributeListDef!S aItem)
    {
        _defs ~= aItem;
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putDocumentTypeAttributeListBegin(name);
        foreach (e; _defs)
            e.write(aWriter);
        aWriter.putDocumentTypeAttributeListEnd();

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.documentTypeAttributeList;
    }
}

class XmlDocumentTypeAttributeListDef(S) : XmlObject!S
{
protected:
    XmlDocument!S _ownerDocument;
    XmlDocumentTypeAttributeListDefType!S _type;
    XmlString!S _defaultDeclareText;
    S _defaultDeclareType;

package:
    this(XmlDocument!S aOwnerDocument, XmlDocumentTypeAttributeListDefType!S aType,
            S aDefaultDeclareType, XmlString!S aDefaultDeclareText)
    {
        _ownerDocument = aOwnerDocument;
        _type = aType;
        _defaultDeclareType = aDefaultDeclareType;
        _defaultDeclareText = aDefaultDeclareText;
    }

public:
    this(XmlDocument!S aOwnerDocument, XmlDocumentTypeAttributeListDefType!S aType,
            S aDefaultDeclareType, S aDefaultDeclareText)
    {
        this(aOwnerDocument, aType, aDefaultDeclareType, XmlString!S(aDefaultDeclareText));
    }

    final XmlWriter!S write(XmlWriter!S aWriter)
    {
        if (_type !is null)
            _type.write(aWriter);

        if (_defaultDeclareType.length > 0)
            aWriter.putWithPreSpace(_defaultDeclareType);

        if (_defaultDeclareText.length > 0)
        {
            aWriter.put(' ');
            aWriter.putWithQuote(ownerDocument.getEncodeText(_defaultDeclareText));
        }

        return aWriter;
    }

@property:
    final S defaultDeclareText()
    {
        return ownerDocument.getDecodeText(_defaultDeclareText);
    }

    final S defaultDeclareType()
    {
        return _defaultDeclareType;
    }

    final XmlDocument!S ownerDocument()
    {
        return _ownerDocument;
    }

    final XmlDocumentTypeAttributeListDefType!S type()
    {
        return _type;
    }
}

class XmlDocumentTypeAttributeListDefType(S) : XmlObject!S
{
protected:
    XmlDocument!S _ownerDocument;
    S _name;
    S _type;
    S[] _items;

public:
    this(XmlDocument!S aOwnerDocument, S aName, S aType, S[] aItems)
    {
        _ownerDocument = aOwnerDocument;
        _name = aName;
        _type = aType;
        _items = aItems;
    }

    final void appendItem(S aItem)
    {
        _items ~= aItem;
    }

    final XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.put(_name);
        aWriter.putWithPreSpace(_type);
        foreach (e; _items)
            aWriter.putWithPreSpace(e);

        return aWriter;
    }

@property:
    final S localName()
    {
        return _name;
    }

    final S name()
    {
        return _name;
    }

    final XmlDocument!S ownerDocument()
    {
        return _ownerDocument;
    }
}

class XmlDocumentTypeElement(S) : XmlNode!S
{
protected:
    XmlDocumentTypeElementItem!S[] _content;

public:
    this(XmlDocument!S aOwnerDocument, S aName)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aName);
    }

    final XmlDocumentTypeElementItem!S appendChoice(S aChoice)
    {
        XmlDocumentTypeElementItem!S item = new XmlDocumentTypeElementItem!S(ownerDocument,
                this, aChoice);
        _content ~= item;
        return item;
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putDocumentTypeElementBegin(name);

        if (_content.length > 0)
        {
            if (_content.length > 1)
                aWriter.put('(');
            _content[0].write(aWriter);
            foreach (e; _content[1 .. $])
            {
                aWriter.put(',');
                e.write(aWriter);
            }
            if (_content.length > 1)
                aWriter.put(')');
        }

        aWriter.putDocumentTypeElementEnd();

        return aWriter;
    }

@property:
    final XmlDocumentTypeElementItem!S[] content()
    {
        return _content;
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.documentTypeElement;
    }
}

class XmlDocumentTypeElementItem(S) : XmlObject!S
{
protected:
    XmlDocument!S _ownerDocument;
    XmlNode!S _parent;
    XmlDocumentTypeElementItem!S[] _subChoices;
    S _choice; // EMPTY | ANY | #PCDATA | any-name
    C _multiIndicator = 0; // * | ? | + | blank

public:
    this(XmlDocument!S aOwnerDocument, XmlNode!S aParent, S aChoice)
    {
        _ownerDocument = aOwnerDocument;
        _parent = aParent;
        _choice = aChoice;
    }

    XmlDocumentTypeElementItem!S appendChoice(S aChoice)
    {
        XmlDocumentTypeElementItem!S item = new XmlDocumentTypeElementItem!S(ownerDocument,
                parent, aChoice);
        _subChoices ~= item;
        return item;
    }

    final XmlWriter!S write(XmlWriter!S aWriter)
    {
        if (_choice.length > 0)
            aWriter.put(_choice);

        if (_subChoices.length > 0)
        {
            aWriter.put('(');
            _subChoices[0].write(aWriter);
            foreach (e; _subChoices[1 .. $])
            {
                aWriter.put('|');
                e.write(aWriter);
            }
            aWriter.put(')');
        }

        if (_multiIndicator != 0)
            aWriter.put(_multiIndicator);

        return aWriter;
    }

@property:
    final S choice()
    {
        return _choice;
    }

    final C multiIndicator()
    {
        return _multiIndicator;
    }

    final C multiIndicator(C newValue)
    {
        return _multiIndicator = newValue;
    }

    final XmlDocument!S ownerDocument()
    {
        return _ownerDocument;
    }

    final XmlNode!S parent()
    {
        return _parent;
    }

    final XmlDocumentTypeElementItem!S[] subChoices()
    {
        return _subChoices;
    }
}

class XmlElement(S) : XmlNode!S
{
public:
    this(XmlDocument!S aOwnerDocument, XmlName!S aName)
    {
        if (!aOwnerDocument.isLoading())
        {
            checkName!(S, Yes.allowEmpty)(aName.prefix);
            checkName!(S, No.allowEmpty)(aName.localName);
        }

        super(aOwnerDocument);
        _qualifiedName = aName;
    }

    final override bool allowAttribute() const
    {
        return true;
    }

    final override bool allowChild() const
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType aNodeType)
    {
        switch (aNodeType)
        {
            case XmlNodeType.cDataSection:
            case XmlNodeType.comment:
            case XmlNodeType.element:
            case XmlNodeType.entityReference:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.text:
            case XmlNodeType.whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        Flag!"hasAttribute" a;
        if (hasAttributes)
            a = Yes.hasAttribute;

        Flag!"hasChild" c;
        if (hasChildNodes)
            c = Yes.hasChild;

        bool onlyOneNodeText = (isOnlyNode(firstChild) && firstChild.nodeType == XmlNodeType.text);
        if (onlyOneNodeText)
            aWriter.incOnlyOneNodeText();

        if (!a && !c)
            aWriter.putElementEmpty(name);
        else
        {
            aWriter.putElementNameBegin(name, a);

            if (a)
            {
                writeAttributes(aWriter);
                aWriter.putElementNameEnd(name, c);
            }

            if (c)
            {
                writeChildren(aWriter);
                aWriter.putElementEnd(name);
            }
        }

        if (onlyOneNodeText)
            aWriter.decOnlyOneNodeText();

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.element;
    }

    final override S prefix(S newValue)
    {
        _qualifiedName = ownerDocument.createName(newValue, localName, namespaceUri);
        return newValue;
    }
}

class XmlEntity(S) : XmlEntityCustom!S
{
package:
    this(XmlDocument!S aOwnerDocument, S aName, XmlString!S aValue)
    {
        super(aOwnerDocument, aName, aValue);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aValue, S aNotationName)
    {
        super(aOwnerDocument, aName, aPublicOrSystem, aPublicId, aValue, aNotationName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aName, S aValue)
    {
        super(aOwnerDocument, aName, aValue);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, S aPublicId,
        S aValue, S aNotationName)
    {
        super(aOwnerDocument, aName, aPublicOrSystem, aPublicId, aValue, aNotationName);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putEntityGeneral(name, _publicOrSystem, ownerDocument.getEncodeText(_publicId),
            _notationName, ownerDocument.getEncodeText(_text));

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.entity;
    }
}

class XmlEntityReference(S) : XmlEntityCustom!S
{
package:
    this(XmlDocument!S aOwnerDocument, S aName, XmlString!S aValue)
    {
        super(aOwnerDocument, aName, aValue);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aValue)
    {
        super(aOwnerDocument, aName, aPublicOrSystem, aPublicId, aValue, null);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aName, S aValue)
    {
        super(aOwnerDocument, aName, aValue);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, S aPublicId, S aValue)
    {
        super(aOwnerDocument, aName, aPublicOrSystem, aPublicId, aValue, null);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putEntityReference(name, _publicOrSystem, ownerDocument.getEncodeText(_publicId),
            _notationName, ownerDocument.getEncodeText(_text));

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.entityReference;
    }
}

class XmlNotation(S) : XmlNode!S
{
protected:
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;

    this(XmlDocument!S aOwnerDocument, S aName)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aName);
    }

package:
    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = aPublicId;
        _text = aText;
    }

public:
    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, S aPublicId, S aText)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = XmlString!S(aPublicId);
        _text = XmlString!S(aText);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putNotation(name, publicOrSystem, ownerDocument.getEncodeText(_publicId),
            ownerDocument.getEncodeText(_text));

        return aWriter;
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.notation;
    }

    final S publicId()
    {
        return ownerDocument.getDecodeText(_publicId);
    }

    final S publicOrSystem()
    {
        return _publicOrSystem;
    }

    final override S value()
    {
        return ownerDocument.getDecodeText(_text);
    }

    final override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlProcessingInstruction(S) : XmlNode!S
{
protected:
    XmlString!S _text;

    this(XmlDocument!S aOwnerDocument, S aTarget)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aTarget);
    }

package:
    this(XmlDocument!S aOwnerDocument, S aTarget, XmlString!S aText)
    {
        this(aOwnerDocument, aTarget);
        _text = aText;
    }

public:
    this(XmlDocument!S aOwnerDocument, S aTarget, S aText)
    {
        this(aOwnerDocument, aTarget);
        _text = XmlString!S(aText);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.putProcessingInstruction(name, ownerDocument.getEncodeText(_text));

        return aWriter;
    }

@property:
    final override S innerText()
    {
        return value;
    }

    final override S innerText(S newValue)
    {
        return value(newValue);
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.processingInstruction;
    }

    final S target()
    {
        return _qualifiedName.name;
    }

    final override S value()
    {
        return ownerDocument.getDecodeText(_text); 
    }

    final override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlSignificantWhitespace(S) : XmlCharacterWhitespace!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.significantWhitespaceTagName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.significantWhitespace;
    }
}

class XmlText(S) : XmlCharacterData!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.textTagName);
    }

package:
    this(XmlDocument!S aOwnerDocument, XmlString!S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        aWriter.put(ownerDocument.getEncodeText(_text));

        return aWriter;
    }

@property:
    final override size_t level()
    {
        if (parentNode is null)
            return 0;
        else
            return parentNode.level;
    }

    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.text;
    }
}

class XmlWhitespace(S) : XmlCharacterWhitespace!S
{
protected:
    __gshared static XmlName!S _defaultQualifiedName;

    static XmlName!S createDefaultQualifiedName()
    {
        return new XmlName!S(XmlConst.whitespaceTagName);
    }

public:
    this(XmlDocument!S aOwnerDocument, S aText)
    {
        super(aOwnerDocument, aText);
        _qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

@property:
    final override XmlNodeType nodeType() const
    {
        return XmlNodeType.whitespace;
    }
}

class XmlCharacterData(S) : XmlNode!S
{
protected:
    XmlString!S _text;

    final override bool isText() const
    {
        return true;
    }

    this(XmlDocument!S aOwnerDocument, S aText)
    {
        this(aOwnerDocument, aText, XmlEncodeMode.check);
    }

    this(XmlDocument!S aOwnerDocument, S aText, XmlEncodeMode aMode)
    {
        this(aOwnerDocument, XmlString!S(aText, aMode));
    }

    this(XmlDocument!S aOwnerDocument, XmlString!S aText)
    {
        super(aOwnerDocument);
        _text = aText;
    }

public:
@property:
    final override S innerText()
    {
        return value;
    }

    final override S innerText(S newValue)
    {
        return value(newValue);
    }

    override S value()
    {
        return ownerDocument.getDecodeText(_text);
    }

    override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlCharacterWhitespace(S) : XmlCharacterData!S
{
protected:
    final S checkWhitespaces(S aText)
    {
        if (!isSpaces(aText))
            throw new XmlException(Message.eNotAllWhitespaces);
        return aText;
    }

public:
    this(XmlDocument!S aOwnerDocument, S aText)
    {
        if (!aOwnerDocument.isLoading())
            checkWhitespaces(aText);

        super(aOwnerDocument, XmlString!S(aText, XmlEncodeMode.none));
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        if (_text.length > 0)
            aWriter.put(_text.value);

        return aWriter;
    }

@property:
    final override size_t level()
    {
        if (parentNode is null)
            return 0;
        else
            return parentNode.level;
    }

    final override S value()
    {
        return _text.toString();
    }

    final override S value(S newValue)
    {
        _text = checkWhitespaces(newValue);
        return newValue;
    }
}

class XmlEntityCustom(S) : XmlNode!S
{
protected:
    S _notationName;
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;

    this(XmlDocument!S aOwnerDocument, S aName)
    {
        super(aOwnerDocument);
        _qualifiedName = new XmlName!S(aName);
    }

    this(XmlDocument!S aOwnerDocument, S aName, XmlString!S aText)
    {
        this(aOwnerDocument, aName);
        _text = aText;
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem,
        XmlString!S aPublicId, XmlString!S aText, S aNotationName)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = aPublicId;
        _text = aText;
        _notationName = aNotationName;
    }

public:
    this(XmlDocument!S aOwnerDocument, S aName, S aText)
    {
        this(aOwnerDocument, aName);
        _text = XmlString!S(aText);
    }

    this(XmlDocument!S aOwnerDocument, S aName, S aPublicOrSystem, S aPublicId,
        S aText, S aNotationName)
    {
        this(aOwnerDocument, aName);
        _publicOrSystem = aPublicOrSystem;
        _publicId = XmlString!S(aPublicId);
        _text = XmlString!S(aText);
        _notationName = aNotationName;
    }

@property:
    final S notationName()
    {
        return _notationName;
    }

    final S publicId()
    {
        return ownerDocument.getDecodeText(_publicId);
    }

    final S publicOrSystem()
    {
        return _publicOrSystem;
    }

    final override S value()
    {
        return ownerDocument.getDecodeText(_text);
    }

    final override S value(S newValue)
    {
        _text = newValue;
        return newValue;
    }
}

class XmlName(S) : XmlObject!S
{
protected:
    XmlDocument!S ownerDocument;
    S _localName;
    S _name;
    S _namespaceUri;
    S _prefix;

    final void callSplitName()
    {
        if (ownerDocument is null)
            splitName(name, _prefix, _localName);
        else
        {
            S p, l;
            splitName(name, p, l);
            _prefix = ownerDocument.addSymbolIf(p);
            _localName = ownerDocument.addSymbolIf(l);
        }
    }

package:
    this(S aStaticName)
    {
        _localName = aStaticName;
        _name = aStaticName;
    }

public:
    this(XmlDocument!S aOwnerDocument, S aPrefix, S aLocalName, S aNamespaceUri)
    {
        ownerDocument = aOwnerDocument; 
        _prefix = aOwnerDocument.addSymbolIf(aPrefix);
        _localName = aOwnerDocument.addSymbolIf(aLocalName);
        _namespaceUri = aOwnerDocument.addSymbolIf(aNamespaceUri);

        if (aPrefix.length == 0)
            _name = aLocalName;
    }

    this(XmlDocument!S aOwnerDocument, S aQualifiedName)
    {
        ownerDocument = aOwnerDocument; 
        _name = aOwnerDocument.addSymbolIf(aQualifiedName);
    }

@property:
    final S localName()
    {
        if (_localName is null)
            callSplitName();            

        return _localName;
    }

    final S name()
    {
        if (_name is null)
        {
            if (ownerDocument is null)
                _name = combineName(prefix, localName);
            else
                _name = ownerDocument.addSymbolIf(combineName(prefix, localName));
        }

        return _name;
    }

    final S namespaceUri()
    {
        if (_namespaceUri is null)
        {
            bool function(const(C)[] s1, const(C)[] s2) equalName;
            if (ownerDocument is null)
                equalName = &equalCase!S;
            else
                equalName = ownerDocument.equalName;
            if (equalName(prefix, XmlConst.xmlns) || (prefix.length == 0 && equalName(localName, XmlConst.xmlns)))
                _namespaceUri = XmlConst.xmlnsNS;
            else if (equalName(prefix, XmlConst.xml))
                _namespaceUri = XmlConst.xmlNS;
            else if (ownerDocument !is null)
                _namespaceUri = ownerDocument.defaultUri;
            else
                _namespaceUri = "";
        }

        return _namespaceUri;
    }

    final S prefix()
    {
        if (_prefix is null)
            callSplitName();

        return _prefix;
    }
}

unittest  // XmlDocument
{
    outputXmlTraceProgress("unittest XmlDocument");

    auto doc = new XmlDocument!string();
    auto root = doc.appendChild(doc.createElement("root"));
    root.appendChild(doc.createElement("prefix", "localname", null));
    root.appendChild(doc.createElement("a"))
        .appendAttribute(doc.createAttribute("a", "value"));
    root.appendChild(doc.createElement("a2"))
        .appendAttribute(doc.createAttribute("a2", "&<>'\""));
    root.appendChild(doc.createElement("c"))
        .appendChild(doc.createComment("comment"));
    root.appendChild(doc.createElement("t"))
        .appendChild(doc.createText("text"));
    root.appendChild(doc.createCDataSection("data &<>"));

    assert(doc.outerXml() == "<root><prefix:localname/><a a=\"value\"/><a2 a2=\"&amp;&lt;&gt;&apos;&quot;\"/><c><!-- comment --></c><t>text</t><![CDATA[data &<>]]></root>");
}