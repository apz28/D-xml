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

module pham.xml_xpath;

import std.conv : to;
import std.typecons : No, Yes;
import std.math : isNaN;
import std.format : format;
import std.variant;

import pham.xml_msg;
import pham.xml_exception;
import pham.xml_util;
import pham.xml_object;
import pham.xml_writer;
import pham.xml_new;

enum XPathAxisType
{
    error,
    ancestor,
    ancestorOrSelf,
    attribute,
    child,
    descendant,
    descendantOrSelf,
    following,
    followingSibling,
    namespace,
    parent,
    preceding,
    precedingSibling,
    self
}

enum XPathAstType
{
    error,
    axis,
    constant,
    filter,
    function_,
    group,
    operator,
    root,
    variable
}

enum XPathCaseOrder
{
    none,
    upperFirst,
    lowerFirst
}

enum XPathDataType
{
    boolean,
    number,
    text
}

enum XPathFunctionType
{
    boolean,
    ceiling,
    concat,
    contains,
    count,
    false_,
    true_,
    floor,
    id,
    lang,
    last,
    localName,
    name,
    namespaceUri,
    normalize,
    not,
    number,
    position,
    round,
    startsWith,
    stringLength,
    substring,
    substringAfter,
    substringBefore,
    sum,
    text,
    translate,
    userDefined
}

enum XPathNodeType
{
    all,
    attribute,
    comment,
    element,
    namespace,
    processingInstruction,
    root,
    significantWhitespace,
    text,
    whitespace
}

enum XPathOp
{
    error,
    // Logical   
    and,
    or,
    // Equality  
    eq,
    ne,
    // Relational
    lt,
    le,
    gt,
    ge,
    // Arithmetic
    plus,
    minus,
    multiply,
    divide,
    mod,
    // Union     
    union_
}

enum XPathResultType
{
    error,
    any,
    boolean,
    nodeSet,
    number,
    text,
    navigator = XPathResultType.text
}

enum XPathSortOrder
{
    ascending,
    descending
}

alias ToResultTypeTable = EnumArray!(XPathFunctionType, XPathResultType); 
immutable ToResultTypeTable toResultTypeTable = ToResultTypeTable(
    ToResultTypeTable.Entry(XPathFunctionType.boolean, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.ceiling, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.concat, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.contains, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.count, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.false_, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.true_, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.floor, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.id, XPathResultType.nodeSet),
    ToResultTypeTable.Entry(XPathFunctionType.lang, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.last, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.localName, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.name, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.namespaceUri, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.normalize, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.not, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.number, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.position, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.round, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.startsWith, XPathResultType.boolean),
    ToResultTypeTable.Entry(XPathFunctionType.stringLength, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.text, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.substring, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.substringAfter, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.substringBefore, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.sum, XPathResultType.number),
    ToResultTypeTable.Entry(XPathFunctionType.translate, XPathResultType.text),
    ToResultTypeTable.Entry(XPathFunctionType.userDefined, XPathResultType.any)
);

pragma(inline, true)
XPathResultType toResultType(XPathFunctionType aFunctionType) pure nothrow @safe
{
    return toResultTypeTable[aFunctionType];
}

alias InvertedOpTable = EnumArray!(XPathOp, XPathOp);
immutable InvertedOpTable invertedOpTable = InvertedOpTable(
    InvertedOpTable.Entry(XPathOp.error, XPathOp.error),
    InvertedOpTable.Entry(XPathOp.and, XPathOp.or),
    InvertedOpTable.Entry(XPathOp.or, XPathOp.and),
    InvertedOpTable.Entry(XPathOp.eq, XPathOp.ne),
    InvertedOpTable.Entry(XPathOp.ne, XPathOp.eq),
    InvertedOpTable.Entry(XPathOp.lt, XPathOp.gt),
    InvertedOpTable.Entry(XPathOp.le, XPathOp.ge),
    InvertedOpTable.Entry(XPathOp.gt, XPathOp.lt),
    InvertedOpTable.Entry(XPathOp.ge, XPathOp.le),
    InvertedOpTable.Entry(XPathOp.plus, XPathOp.minus),
    InvertedOpTable.Entry(XPathOp.minus, XPathOp.plus),
    InvertedOpTable.Entry(XPathOp.multiply, XPathOp.divide),
    InvertedOpTable.Entry(XPathOp.divide, XPathOp.multiply),
    InvertedOpTable.Entry(XPathOp.mod, XPathOp.error),
    InvertedOpTable.Entry(XPathOp.union_, XPathOp.error)
);

pragma(inline, true)
XPathOp invertedOp(XPathOp op) pure nothrow @safe
{
    return invertedOpTable[op];
}

alias ToXmlNodeTypeTable = EnumArray!(XPathNodeType, XmlNodeType);
immutable ToXmlNodeTypeTable toXmlNodeTypeTable = ToXmlNodeTypeTable(
    ToXmlNodeTypeTable.Entry(XPathNodeType.all, XmlNodeType.unknown),
    ToXmlNodeTypeTable.Entry(XPathNodeType.attribute, XmlNodeType.attribute),
    ToXmlNodeTypeTable.Entry(XPathNodeType.comment, XmlNodeType.comment),
    ToXmlNodeTypeTable.Entry(XPathNodeType.element, XmlNodeType.element),
    ToXmlNodeTypeTable.Entry(XPathNodeType.namespace, XmlNodeType.attribute),
    ToXmlNodeTypeTable.Entry(XPathNodeType.processingInstruction, XmlNodeType.processingInstruction),
    ToXmlNodeTypeTable.Entry(XPathNodeType.root, XmlNodeType.document),
    ToXmlNodeTypeTable.Entry(XPathNodeType.significantWhitespace, XmlNodeType.significantWhitespace),
    ToXmlNodeTypeTable.Entry(XPathNodeType.text, XmlNodeType.text),
    ToXmlNodeTypeTable.Entry(XPathNodeType.whitespace, XmlNodeType.whitespace)
); 

pragma(inline, true)
XmlNodeType toXmlNodeType(XPathNodeType aNodeType) pure nothrow @safe
{
    return toXmlNodeTypeTable[aNodeType];
}


private bool toBoolean(double value) pure nothrow @safe
{
    return (!isNaN(value) && value != 0);
}

private bool toBoolean(S)(const S value) pure nothrow @safe
if (isXmlString!S)
{
    return (value == "1" || value == XmlConst.sTrue || value == XmlConst.yes);
}

private double toNumber(bool value) pure nothrow @safe
{
    if (value)
        return 1.0;
    else
        return 0.0;
}

private double toNumber(S)(S value) pure @safe
if (isXmlString!S)
{
    import std.string : strip;

    value = strip(value);
    if (value.length == 0)
        return double.nan;
    else
        return to!double(value);
}

private S toText(S)(bool value) pure nothrow @safe
if (isXmlString!S)
{
    if (value)
        return XmlConst.sTrue;
    else
        return XmlConst.sFalse;
}

private S toText(S)(double value) @safe
if (isXmlString!S)
{
    import std.math : isInfinity, signbit;

    if (isNaN(value))
        return "NaN";
    else if (isInfinity(value))
    {
        if (signbit(value))
            return "-Infinity";
        else
            return "Infinity";
    }
    else
        return to!S(value);
}

private S toText(S)(XmlNode!S aNode)
if (isXmlString!S)
{
    if (aNode.hasValue(No.checkContent))
        return aNode.value;
    else
        return aNode.innerText;
}

private XPathDataType valueDataType(const Variant aValue)
{
    if (aValue.peek!double)
        return XPathDataType.number;
    else if (aValue.peek!bool)
        return XPathDataType.boolean;
    else
        return XPathDataType.text;
}

private void normalizeValueToBoolean(S)(ref Variant v, XPathDataType vType)
{
    if (vType == XPathDataType.number)
        v = Variant(toBoolean(v.get!double));
    else if (vType == XPathDataType.text)
        v = Variant(toBoolean!S(v.get!S));
}

private void normalizeValueToBoolean(S)(ref Variant v)
{
    normalizeValueToBoolean!S(v, valueDataType(v));
}

private void normalizeValueToNumber(S)(ref Variant v, XPathDataType vType)
{
    if (vType == XPathDataType.boolean)
        v = Variant(toNumber(v.get!bool));
    else if (vType == XPathDataType.text)
        v = Variant(toNumber!S(v.get!S));
}

private void normalizeValueToNumber(S)(ref Variant v)
{
    normalizeValueToNumber!S(v, valueDataType(v));
}

private void normalizeValueToText(S)(ref Variant v, XPathDataType vType)
{
    if (vType == XPathDataType.boolean)
        v = Variant(toText!S(v.get!bool));
    else if (vType == XPathDataType.number)
        v = Variant(toText!S(v.get!double));
}

private void normalizeValueToText(S)(ref Variant v)
{
    normalizeValueToText!S(v, valueDataType(v));
}

private void normalizeValueTo(S)(ref Variant value, XPathDataType toT)
{
    XPathDataType vType = valueDataType(value);
    if (vType != toT)
    {
        final switch (toT)
        {
            case XPathDataType.boolean:
                normalizeValueToBoolean!S(value, vType);
                break;
            case XPathDataType.number:
                normalizeValueToNumber!S(value, vType);
                break;
            case XPathDataType.text:
                normalizeValueToText!S(value, vType);
                break;
        }
    }
}

private void normalizeValues(S)(ref Variant value1, ref Variant value2)
{
    XPathDataType t1 = valueDataType(value1);
    XPathDataType t2 = valueDataType(value2);

    if (t1 != t2)
    {
        if (t1 == XPathDataType.number || t2 == XPathDataType.number)
        {
            if (t1 != XPathDataType.number)
                normalizeValueToNumber!S(value1, t1);
            if (t2 != XPathDataType.number)
                normalizeValueToNumber!S(value2, t2);
        }
        else
        {
            if (t1 != XPathDataType.text)
                normalizeValueToText!S(value1, t1);
            if (t2 != XPathDataType.text)
                normalizeValueToText!S(value2, t2);
        }
    }
}


struct XPathContext(S)
if (isXmlString!S)
{
private:
    XmlNode!S _xpathNode;
    XmlElement!S _xpathDocumentElement;

package:
    debug (traceXmlXPathParser) 
    {
        static size_t _nodeIndent;

        size_t* nodeIndent;

        void decNodeIndent()
        {
            *nodeIndent -= 1;
        }

        void incNodeIndent()
        {
            *nodeIndent += 1;
        }

        string indentString()
        {
            return stringOfChar!string(' ', (*nodeIndent) << 1);
        }
    }

public:
    XmlNodeList!S resNodes = XmlNodeList!S(null);
    Variant resValue;

    XmlNodeList!S filterNodes;
    Variant[S] variables;

    @disable this();

    this(XmlNode!S aXPathNode)
    {
        debug (traceXmlXPathParser) 
            nodeIndent = &_nodeIndent;

        _xpathNode = aXPathNode;
    }

    void clear()
    {
        if (!resNodes.empty)
            resNodes = XmlNodeList!S(null);
        resValue = Variant(null);
    }

    XPathContext!S createOutputContext()
    {
        XPathContext!S result = XPathContext!S(_xpathNode);
        result._xpathDocumentElement = _xpathDocumentElement;
        result.variables = variables;
        result.filterNodes = filterNodes;

        return result;
    }

    XmlDocument!S xpathDocument()
    {
        return xpathNode.document();
    }

@property:
    XmlNode!S xpathNode()
    {
        return _xpathNode;
    }

    XmlElement!S xpathDocumentElement()
    {
        if (_xpathDocumentElement is null)
            _xpathDocumentElement = xpathDocument().documentElement();
        return _xpathDocumentElement;
    }
}

abstract class XPathNode(S) : XmlObject!S
{
protected:
    alias XPathAstNodeEvaluate = void delegate(
        ref XPathContext!S inputContext,
        ref XPathContext!S outputContext);

    const(C)[] _localName;
    const(C)[] _prefix;
    S _qualifiedName;
    XPathNode!S _parent;

    final void evaluateError(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "evaluate()");
    }

public:
    T get(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == bool))
    {
        XPathContext!S tempOutputContext = inputContext.createOutputContext();
        evaluate(inputContext, tempOutputContext);

        if (tempOutputContext.resValue.hasValue)
        {
            static if (is(T == bool))
            {
                normalizeValueToBoolean!S(tempOutputContext.resValue);
                return tempOutputContext.resValue.get!bool;
            }
            else static if (is(T == double))
            {
                normalizeValueToNumber!S(tempOutputContext.resValue);
                return tempOutputContext.resValue.get!double;
            }
            else
            {
                normalizeValueToText!S(tempOutputContext.resValue);
                return tempOutputContext.resValue.get!S;
            }
        }
        else
        {
            static if (is(T == bool))
                return (!tempOutputContext.resNodes.empty);
            else static if (is(T == double))
            {
                if (tempOutputContext.resNodes.empty)
                    return double.nan;
                else
                    return toNumber!S(tempOutputContext.resNodes.front.toText());
            }
            else
            {
                if (tempOutputContext.resNodes.empty)
                    return null;
                else
                    return tempOutputContext.resNodes.front.toText();
            }
        }
    }

    final S qualifiedName()
    {
        if (_qualifiedName is null)
            _qualifiedName = combineName!S(_prefix.idup, _localName.idup);

        return _qualifiedName;
    }

    final override S toString()
    {
        auto buffer = new XmlBuffer!(S, false)();
        write(new XmlStringWriter!S(No.PrettyOutput, buffer));
        return buffer.toString();
    }

    abstract void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext);

    abstract XmlWriter!S write(XmlWriter!S aWriter);

@property:
    final XPathNode!S parent()
    {
        return _parent;
    }

    abstract XPathAstType astType() const;
    abstract XPathResultType returnType() const;
}

class XPathAxis(S) : XPathNode!S
{
protected:
    XPathAstNodeEvaluate evaluateFct;
    XPathNode!S _input;
    XPathAxisType _axisType;
    XPathNodeType _axisNodeType;
    XmlNodeType _xmlNodeType;
    bool _abbreviated, _xmlMatchAnyName;

    final bool accept(XmlNode!S aNode)
    {
        // XmlNodeType.unknown = all
        bool result = (_xmlNodeType == XmlNodeType.unknown || aNode.nodeType == _xmlNodeType);

        if (!_xmlMatchAnyName)
        {
            const equalName = aNode.document.equalName;
            if (result && prefix.length > 0)
                result = equalName(aNode.prefix, prefix);
            if (result && localName.length > 0)
                result = equalName(aNode.localName, localName);
        }

        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s%s.accept(name: %s): %s", inputContext.indentString, shortClassName, aNode.name, result);
        }

        return result;
    }

    final void evaluateAncestor(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto p = e.parentNode;
            while (p !is null)
            {
                if (accept(p))
                    outputContext.resNodes.insertBack(p);
                p = p.parentNode;
            }
        }

        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s%s.evaluateAncestor(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateAncestorOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (accept(e))
                outputContext.resNodes.insertBack(e);

            auto p = e.parentNode;
            while (p !is null)
            {
                if (accept(p))
                    outputContext.resNodes.insertBack(p);
                p = p.parentNode;
            }
        }        

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateAncestorOrSelf(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateAttribute(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.element && e.hasAttributes)
            {
                auto attributes = e.attributes;
                foreach (a; attributes)
                {
                    if (accept(a))
                        outputContext.resNodes.insertBack(a);
                }
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateAttribute(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateChild(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (!e.hasChildNodes)
                continue;

            auto childNodes = e.childNodes;
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateChild(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateDescendant(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateDescendant(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateDescendantOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType != XmlNodeType.attribute && accept(e))
                outputContext.resNodes.insertBack(e);

            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateDescendantOrSelf(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateFollowing(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            if (n !is null && accept(n))
                outputContext.resNodes.insertBack(n);
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateFollowing(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateFollowingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            while (n !is null)
            {
                if (accept(n))
                    outputContext.resNodes.insertBack(n);
                n = n.nextSibling;
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateFollowingSibling(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateNamespace(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType != XmlNodeType.element || !e.hasAttributes)
                continue;

            XmlNodeList!S attributes = e.attributes;
            foreach (a; attributes)
            {
                if (accept(a))
                    outputContext.resNodes.insertBack(a);
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateNamespace(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateParent(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto p = e.parentNode;
            if (p !is null && accept(p))
                outputContext.resNodes.insertBack(p);
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateParent(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluatePreceding(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            if (n !is null && accept(n))
                outputContext.resNodes.insertBack(n);
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluatePreceding(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluatePrecedingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            while (n !is null)
            {
                if (accept(n))
                    outputContext.resNodes.insertBack(n);
                n = n.previousSibling;
            }
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluatePrecedingSibling(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

    final void evaluateSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (accept(e))
                outputContext.resNodes.insertBack(e);
        }

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluateSelf(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                outputContext.resNodes.length);
        }
    }

public:
    this(XPathNode!S aParent, XPathAxisType aAxisType, XPathNode!S aInput,
        XPathNodeType aNodetype, const(C)[] aPrefix, const(C)[] aLocalName)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(axisType: %s, input: %s, nodeType: %s, prefix: %s, localName: %s)", 
                shortClassName, aAxisType, getShortClassName!S(aInput), aNodetype, aPrefix, aLocalName);
        }

        _parent = aParent;
        _input = aInput;
        _axisType = aAxisType;
        _axisNodeType = aNodetype;
        _prefix = aPrefix;
        _localName = aLocalName;

        _xmlMatchAnyName = aLocalName == "*";
        _xmlNodeType = toXmlNodeType(aNodetype);
        switch (aAxisType)
        {
            case XPathAxisType.error:
                evaluateFct = &evaluateError;
                break;
            case XPathAxisType.ancestor:
                evaluateFct = &evaluateAncestor;
                break;
            case XPathAxisType.ancestorOrSelf:
                evaluateFct = &evaluateAncestorOrSelf;
                break;
            case XPathAxisType.attribute:
                evaluateFct = &evaluateAttribute;
                break;
            case XPathAxisType.child:
                evaluateFct = &evaluateChild;
                break;
            case XPathAxisType.descendant:
                evaluateFct = &evaluateDescendant;
                break;
            case XPathAxisType.descendantOrSelf:
                evaluateFct = &evaluateDescendantOrSelf;
                break;
            case XPathAxisType.following:
                evaluateFct = &evaluateFollowing;
                break;
            case XPathAxisType.followingSibling:
                evaluateFct = &evaluateFollowingSibling;
                break;
            case XPathAxisType.namespace:
                evaluateFct = &evaluateNamespace;
                break;
            case XPathAxisType.parent:
                evaluateFct = &evaluateParent;
                break;
            case XPathAxisType.preceding:
                evaluateFct = &evaluatePreceding;
                break;
            case XPathAxisType.precedingSibling:
                evaluateFct = &evaluatePrecedingSibling;
                break;
            case XPathAxisType.self:
                evaluateFct = &evaluateSelf;
                break;
            default:
                assert(0);
        }
    }

    this(XPathNode!S aParent, XPathAxisType aAxisType, XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(axisType: %s, input: %s)", shortClassName, aAxisType, getShortClassName!S(aInput));
        }

        this(aParent, aAxisType, aInput, XPathNodeType.all, null, null);
        _abbreviated = true;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {        
            import std.stdio : writefln;

            writefln("%s%s.evaluate(axisType: %s, nodeType: %s, abbreviated: %s, qName: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, axisType, nodeType, abbreviated, qualifiedName(),
                inputContext.resNodes.length);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        if (input !is null)
        {
            XPathContext!S inputContextCond = inputContext.createOutputContext();
            input.evaluate(inputContext, inputContextCond);

            evaluateFct(inputContextCond, outputContext);
        }
        else
            evaluateFct(inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser) 
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.putAttribute(format("::name(axisType=%s, nodeType=%s, abbreviated=%s)",
                axisType, nodeType, abbreviated), qualifiedName());

        if (input !is null)
        {
            aWriter.incNodeLevel();
            input.write(aWriter.putLF());
            aWriter.decNodeLevel();
        }

        return aWriter;
    }

@property:
    final bool abbreviated() const
    {
        return _abbreviated;
    }

    final override XPathAstType astType() const
    {
        return XPathAstType.axis;
    }

    final XPathAxisType axisType() const
    {
        return _axisType;
    }

    final XPathNode!S input()
    {
        return _input;
    }

    final const(C)[] localName() const
    {
        return _localName;
    }

    final const(C)[] prefix() const
    {
        return _prefix;
    }

    final XPathNodeType nodeType() const
    {
        return _axisNodeType;
    }

    final override XPathResultType returnType() const
    {
        return XPathResultType.nodeSet;
    }
}

class XPathFilter(S) : XPathNode!S
{
protected:
    XPathNode!S _input, _condition;

public:
    this(XPathNode!S aParent, XPathNode!S aInput, XPathNode!S aCondition)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(input: %s, condition: %s)", shortClassName, 
                getShortClassName!S(aInput), getShortClassName!S(aCondition));
        }

        _parent = aParent;
        _input = aInput;
        _condition = aCondition;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s%s.evaluate(input: %s, condition: %s, nodeListCount: %d)", 
                inputContext.indentString, shortClassName,
                getShortClassName!S(input), getShortClassName!S(condition),
                inputContext.resNodes.length);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        XPathContext!S inputContextEval = inputContext.createOutputContext();
        input.evaluate(inputContext, inputContextEval);

        if (!inputContextEval.resNodes.empty)
        {
            XPathContext!S outputContextCond = inputContextEval.createOutputContext();

            XPathContext!S inputContextCond = inputContextEval.createOutputContext();
            inputContextCond.filterNodes = inputContextEval.resNodes;

            for (size_t i = 0; i < inputContextEval.resNodes.length; ++i)
            {
                auto e = inputContextEval.resNodes.item(i);

                inputContextCond.clear();
                inputContextCond.resNodes.insertBack(e);

                outputContextCond.clear();
                condition.evaluate(inputContextCond, outputContextCond);

                if (outputContextCond.resValue.hasValue)
                {
                    Variant v = outputContextCond.resValue;
                    normalizeValueToBoolean!S(v);
                    if (v.get!bool)
                        outputContext.resNodes.insertBack(e);
                }
            }
        }
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.incNodeLevel();
        input.write(aWriter.putLF());
        condition.write(aWriter.putLF());
        aWriter.decNodeLevel();

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.filter;
    }

    final XPathNode!S condition()
    {
        return _condition;
    }

    final XPathNode!S input()
    {
        return _input;
    }

    final override XPathResultType returnType() const
    {
        return XPathResultType.nodeSet;
    }
}

private void fctBoolean(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    bool result = context.argumentList[0].get!bool(inputContext);

    outputContext.resValue = Variant(result);
}

private void fctCeiling(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : ceil;

    double result = ceil(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = Variant(result);
}

private void fctConcat(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S s;
    foreach (e; context.argumentList)
        s ~= e.get!S(inputContext);

    outputContext.resValue = Variant(s);
}

private void fctContains(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.string : indexOf;

    S s1 = context.argumentList[0].get!S(inputContext);
    S s2 = context.argumentList[1].get!S(inputContext);
    bool result = s1.indexOf(s2) >= 0;

    outputContext.resValue = Variant(result);
}

private void fctCount(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    XPathContext!S tempOutputContext = inputContext.createOutputContext();
    context.argumentList[0].evaluate(inputContext, tempOutputContext);
    double result = tempOutputContext.resNodes.length;

    outputContext.resValue = Variant(result);
}

private void fctFalse(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    outputContext.resValue = Variant(false);
}

private void fctTrue(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    outputContext.resValue = Variant(true);
}

private void fctFloor(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : floor;

    double result = floor(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = Variant(result);
}

private void fctId(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : find;
    import std.array : empty, split;

    S[] idTokens = context.argumentList[0].get!S(inputContext).split();

    bool hasId(XmlNode!S e)
    {
        if (auto a = e.findAttributeById())
        {
            S av = a.value;
            return !find(idTokens, av).empty;
        }
        else
            return false;
    }

    if (inputContext.resNodes.empty)
    {
        auto nodes = inputContext.xpathDocumentElement.getElements(null, Yes.deep);
        foreach (e; nodes)
        {
            if (hasId(e))
                outputContext.resNodes.insertBack(e);
        }
    }
    else
    {
        for (size_t i = 0; i < inputContext.resNodes.length; ++i)
        {
            auto e = inputContext.resNodes.item(i);
            auto nodes = e.getElements(null, Yes.deep);
            foreach (e2; nodes)
            {
                if (hasId(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }
    }
}

private void fctLang(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : startsWith;

    S lan = context.argumentList[0].get!S(inputContext);

    bool hasLan(XmlNode!S e)
    {
        bool r;
        do
        {
            if (auto a = e.findAttribute("xml:lang"))
            {
                S av = a.value;
                r = av.startsWith(lan);
            }
            e = e.parentNode;
        }
        while (e !is null && !r);
        return r;
    }

    bool result;
    if (lan.length > 0)
    {
        for (size_t i = 0; i < inputContext.resNodes.length; ++i)
        {
            auto e = inputContext.resNodes.item(i);
            result = hasLan(e);
            if (result)
                break;
        }
    }

    outputContext.resValue = Variant(result);
}

private void fctLast(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result = inputContext.resNodes.length;

    outputContext.resValue = Variant(result);
}

private void fctLocalName(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length > 0)
    {
        XPathContext!S tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.localName;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.localName;

    outputContext.resValue = Variant(result);
}

private void fctName(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length > 0)
    {
        XPathContext!S tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.name;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.name;

    outputContext.resValue = Variant(result);
}

private void fctNamespaceUri(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length > 0)
    {
        XPathContext!S tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.namespaceUri;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.namespaceUri;

    outputContext.resValue = Variant(result);
}

private void fctNormalize(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    throw new XmlInvalidOperationException(Message.eInvalidOpFunction, "normalize()");
    //todo
}

private void fctNot(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    bool result = !context.argumentList[0].get!bool(inputContext);

    outputContext.resValue = Variant(result);
}

private void fctNumber(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result = context.argumentList[0].get!double(inputContext);

    outputContext.resValue = Variant(result);
}

private void fctPosition(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result; 
    if (!inputContext.resNodes.empty)
        result = inputContext.filterNodes.position(inputContext.resNodes.front); 

    outputContext.resValue = Variant(result);
}

private void fctRound(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : round;

    double result = round(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = Variant(result);
}

private void fctStartsWith(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : startsWith;

    S s1 = context.argumentList[0].get!S(inputContext);
    S s2 = context.argumentList[1].get!S(inputContext);
    bool result = s1.startsWith(s2);

    outputContext.resValue = Variant(result);
}

private void fctStringLength(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.uni : byGrapheme;

    double result = 0;
    S s;
    if (context.argumentList.length > 0)
        s = context.argumentList[0].get!S(inputContext);
    else if (!inputContext.resNodes.empty)
        s = inputContext.resNodes.front.toText();
    foreach (e; s.byGrapheme)
        result += 1;

    outputContext.resValue = Variant(result);
}

private void fctSubstring(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.comparison : min;

    S result;
    S s = context.argumentList[0].get!S(inputContext);
    int pos = cast(int) context.argumentList[1].get!double(inputContext);
    int cnt = cast(int) context.argumentList[2].get!double(inputContext);

    // Based 1 in xpath, so convert to based 0
    --pos;
    if (cnt > 0 && pos >= 0 && pos < s.length)
        result = rightString(s, min(cnt, s.length - pos));
    else
        result = "";

    outputContext.resValue = Variant(result);
}

private void fctSubstringAfter(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    S s = context.argumentList[0].get!S(inputContext);
    S sub = context.argumentList[1].get!S(inputContext);
    auto searchResult = s.findSplit(sub);

    outputContext.resValue = Variant(searchResult[2]);
}

private void fctSubstringBefore(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    S s = context.argumentList[0].get!S(inputContext);
    S sub = context.argumentList[1].get!S(inputContext);
    auto searchResult = s.findSplit(sub);

    if (searchResult[1] == sub) 
        outputContext.resValue = Variant(searchResult[1]);
    else
        outputContext.resValue = Variant("");
}

private void fctSum(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    XPathContext!S tempOutputContext = inputContext.createOutputContext();
    context.argumentList[0].evaluate(inputContext, tempOutputContext);

    double result = 0.0;
    for (size_t i = 0; i < tempOutputContext.resNodes.length; ++i)
    {
        auto e = inputContext.resNodes.item(i);
        double ev = toNumber!S(e.toText());
        if (!isNaN(ev))
            result += ev;
    }

    outputContext.resValue = Variant(result);
}

private void fctText(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S s = context.get!S(inputContext);

    outputContext.resValue = Variant(s);
}

private void fctTranslate(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    throw new XmlInvalidOperationException(Message.eInvalidOpFunction, "translate()");
    //todo
}

class XPathUserDefinedFunctionEntry(S) : XmlObject!S 
{
private:
    S _localName;
    S _prefix;
    S _qualifiedName;
    XPathFunctionTable!S.XPathFunctionEvaluate _evaluate;
    XPathResultType _resultType;

public:
    this(S aPrefix, S aLocalName, XPathResultType aResultType,
        XPathFunctionTable!S.XPathFunctionEvaluate aEvaluate)
    {
        _prefix = aPrefix;
        _localName = aLocalName;
        _resultType = aResultType;
        _evaluate = aEvaluate;

        _qualifiedName = combineName(_prefix, _localName);
    }

@property:
    final XPathFunctionTable!S.XPathFunctionEvaluate evaluate() const
    {
        return _evaluate;
    }

    final S localName() const
    {
        return _localName;
    }

    final S prefix() const
    {
        return _prefix;
    }

    final S qualifiedName() const
    {
        return _qualifiedName;
    }

    final XPathResultType returnType() const
    {
        return _resultType;
    }
}

class XPathFunctionTable(S) : XmlObject!S
{
public:
    alias XPathFunctionEvaluate = void function(XPathFunction!S context,
        ref XPathContext!S inputContext, ref XPathContext!S outputContext);

protected:
    __gshared static XPathFunctionTable!S _defaultFunctionTable;

    static XPathFunctionTable!S createDefaultFunctionTable()
    {
        return new XPathFunctionTable!S();
    }

protected:
    XPathFunctionEvaluate[S] defaultFunctions;

    final void initDefault()
    {
        defaultFunctions[to!S(XPathFunctionType.boolean)] = &fctBoolean!S;
        defaultFunctions[to!S(XPathFunctionType.ceiling)] = &fctCeiling!S;
        defaultFunctions[to!S(XPathFunctionType.concat)] = &fctConcat!S;
        defaultFunctions[to!S(XPathFunctionType.contains)] = &fctContains!S;
        defaultFunctions[to!S(XPathFunctionType.count)] = &fctCount!S;
        defaultFunctions[to!S(XPathFunctionType.false_)] = &fctFalse!S;
        defaultFunctions[to!S(XPathFunctionType.true_)] = &fctTrue!S;
        defaultFunctions[to!S(XPathFunctionType.floor)] = &fctFloor!S;
        defaultFunctions[to!S(XPathFunctionType.id)] = &fctId!S;
        defaultFunctions[to!S(XPathFunctionType.lang)] = &fctLang!S;
        defaultFunctions[to!S(XPathFunctionType.last)] = &fctLast!S;
        defaultFunctions[to!S(XPathFunctionType.localName)] = &fctLocalName!S;
        defaultFunctions[to!S(XPathFunctionType.name)] = &fctName!S;
        defaultFunctions[to!S(XPathFunctionType.namespaceUri)] = &fctNamespaceUri!S;
        defaultFunctions[to!S(XPathFunctionType.normalize)] = &fctNormalize!S;
        defaultFunctions[to!S(XPathFunctionType.not)] = &fctNot!S;
        defaultFunctions[to!S(XPathFunctionType.number)] = &fctNumber!S;
        defaultFunctions[to!S(XPathFunctionType.position)] = &fctPosition!S;
        defaultFunctions[to!S(XPathFunctionType.round)] = &fctRound!S;
        defaultFunctions[to!S(XPathFunctionType.startsWith)] = &fctStartsWith!S;
        defaultFunctions[to!S(XPathFunctionType.stringLength)] = &fctStringLength!S;
        defaultFunctions[to!S(XPathFunctionType.substring)] = &fctSubstring!S;
        defaultFunctions[to!S(XPathFunctionType.substringAfter)] = &fctSubstringAfter!S;
        defaultFunctions[to!S(XPathFunctionType.substringBefore)] = &fctSubstringBefore!S;
        defaultFunctions[to!S(XPathFunctionType.sum)] = &fctSum!S;
        defaultFunctions[to!S(XPathFunctionType.text)] = &fctText!S;
        defaultFunctions[to!S(XPathFunctionType.translate)] = &fctTranslate!S;
        //defaultFunctions[to!S(XPathFunctionType.)] = &fct!S;

        defaultFunctions.rehash();
    }

public:
    XPathUserDefinedFunctionEntry!S[S] userDefinedFunctions;

    this()
    {
        initDefault();
    }

    static XPathFunctionTable!S defaultFunctionTable()
    {
        return singleton!(XPathFunctionTable!S)(_defaultFunctionTable, &createDefaultFunctionTable);
    }

    final bool find(S aName, ref XPathUserDefinedFunctionEntry!S fct) const
    {
        const(XPathUserDefinedFunctionEntry!S)* r = aName in userDefinedFunctions;

        if (r is null)
            return false;
        else
        {
            fct = cast(XPathUserDefinedFunctionEntry!S)* r;
            return true;
        }
    }

    final bool find(S aName, ref XPathFunctionEvaluate fct) const
    {
        const(XPathFunctionEvaluate)* r = aName in defaultFunctions;

        if (r is null)
        {
            XPathUserDefinedFunctionEntry!S u;
            if (find(aName, u))
            {
                fct = u.evaluate;
                return true;
            }
            else
                return false;
        }
        else
        {
            fct = *r;
            return true;
        }
    }

    alias userDefinedFunctions this;
}

class XPathFunction(S) : XPathNode!S
{
protected:
    XPathUserDefinedFunctionEntry!S userDefinedevaluateFct;
    XPathFunctionTable!S.XPathFunctionEvaluate evaluateFct;
    XPathNode!S[] _argumentList;
    XPathFunctionType _functionType;

    final void setEvaluateFct()
    {
        if (functionType != XPathFunctionType.userDefined)
        {
            XPathFunctionTable!S.defaultFunctionTable().find(to!S(functionType), evaluateFct);

            if (evaluateFct is null)
                throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, to!S(functionType));
        }
        else
        {
            XPathFunctionTable!S.defaultFunctionTable().find(qualifiedName(), userDefinedevaluateFct);
            if (userDefinedevaluateFct is null && prefix.length > 0)
                XPathFunctionTable!S.defaultFunctionTable().find(localName.idup, userDefinedevaluateFct);

            if (userDefinedevaluateFct is null)
                throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, qualifiedName());

            evaluateFct = userDefinedevaluateFct.evaluate;
        }
    }

public:
    this(XPathNode!S aParent, XPathFunctionType aFunctionType, XPathNode!S[] aArgumentList)
    {
        assert(aFunctionType != XPathFunctionType.userDefined);

        debug (traceXmlXPathParser) 
        {            
            import std.stdio : writefln;

            writefln("%s.this(function: %s, argc: %d)", shortClassName, 
                aFunctionType, aArgumentList.length);
        }

        _parent = aParent;
        _functionType = aFunctionType;
        _argumentList = aArgumentList; //aArgumentList.dup();

        setEvaluateFct();
    }

    this(XPathNode!S aParent, const(C)[] aPrefix, const(C)[] aLocalName, XPathNode!S[] aArgumentList)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(prefix: %s, localName: %s, argc: %d)", shortClassName, 
                aPrefix, aLocalName, aArgumentList.length);
        }

        _parent = aParent;
        _functionType = XPathFunctionType.userDefined;
        _prefix = aPrefix;
        _localName = aLocalName;
        _argumentList = aArgumentList; //aArgumentList.dup;

        setEvaluateFct();
    }

    this(XPathNode!S aParent, XPathFunctionType aFunctionType)
    {
        assert(aFunctionType != XPathFunctionType.userDefined);

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(function: %s)", shortClassName, aFunctionType);
        }

        _parent = aParent;
        _functionType = aFunctionType;

        setEvaluateFct();
    }

    this(XPathNode!S aParent, XPathFunctionType aFunctionType, XPathNode!S aArgument)
    {
        assert(aFunctionType != XPathFunctionType.userDefined);

        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(function: %s, argn: %s)", shortClassName, getShortClassName!S(aArgument));
        }

        _parent = aParent;
        _functionType = aFunctionType;
        _argumentList ~= aArgument;

        setEvaluateFct();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s.evaluate(function: %s, returnType: %s, qName: %s, resNodes.length: %d, resValue.hasValue: %d)",
                shortClassName, functionType, returnType, qualifiedName(), inputContext.resNodes.length, inputContext.resValue.hasValue);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        return evaluateFct(this, inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.putAttribute(format("::name(%s:%s)", functionType, returnType), qualifiedName());

        if (argumentList.length > 0)
        {
            aWriter.incNodeLevel();
            foreach (e; argumentList)
                e.write(aWriter.putLF());
            aWriter.decNodeLevel();
        }

        return aWriter;
    }

@property:
    final XPathNode!S[] argumentList()
    {
        return _argumentList;
    }

    final override XPathAstType astType() const
    {
        return XPathAstType.function_;
    }

    final XPathFunctionType functionType() const
    {
        return _functionType;
    }

    final const(C)[] localName()
    {
        return _localName;
    }

    final const(C)[] prefix()
    {
        return _prefix;
    }

    final override XPathResultType returnType() const
    {
        if (functionType == XPathFunctionType.userDefined)
            return userDefinedevaluateFct.returnType;
        else
            return toResultType(functionType);
    }
}

class XPathGroup(S) : XPathNode!S
{
protected:
    XPathNode!S _groupNode;

public:
    this(XPathNode!S aParent, XPathNode!S aGroupNode)
    {
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(group: %s)", shortClassName, getShortClassName!S(aGroupNode));
        }

        _parent = aParent;
        _groupNode = aGroupNode;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        throw new XmlInvalidOperationException(Message.eInvalidOpDelegate, shortClassName, "evaluate()");

        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s%s.evaluate(group: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, getShortClassName!S(groupNode),
                inputContext.resNodes.length);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        //todo
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.incNodeLevel();
        groupNode.write(aWriter.putLF());
        aWriter.decNodeLevel();

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.group;
    }

    final XPathNode!S groupNode()
    {
        return _groupNode;
    }

    final override XPathResultType returnType() const
    {
        return XPathResultType.nodeSet;
    }
}

class XPathOperand(S) : XPathNode!S
{
protected:
    Variant _value;
    XPathResultType _valueType;

public:
    this(XPathNode!S aParent, bool aValue)
    {
        debug (traceXmlXPathParser) 
        {            
            import std.stdio : writefln;

            writefln("%s.this(value: %s)", shortClassName, aValue);
        }

        _parent = aParent;
        _valueType = XPathResultType.boolean;
        _value = aValue;
    }

    this(XPathNode!S aParent, double aValue)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(value: %s)", shortClassName, aValue);
        }

        _parent = aParent;
        _valueType = XPathResultType.number;
        _value = aValue;
    }

    this(XPathNode!S aParent, S aValue)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(value: %s)", shortClassName, aValue);
        }

        _parent = aParent;
        _valueType = XPathResultType.text;
        _value = aValue;
    }

    this(XPathNode!S aParent, const(C)[] aValue)
    {
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.this(value: %s)", shortClassName, aValue);
        }

        _parent = aParent;
        _valueType = XPathResultType.text;
        _value = aValue.idup;
    }

    override T get(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == bool))
    {
        static if (is(T == bool))
        {
            switch (returnType)
            {
                case XPathResultType.boolean:
                    return value.get!bool;
                case XPathResultType.number:
                    return toBoolean(value.get!double);
                case XPathResultType.text:
                    return (value.get!S.length > 0);
                default:
                    assert(0);
            }
        }
        else static if (is(T == double))
        {
            switch (returnType)
            {
                case XPathResultType.boolean:
                    return toNumber(value.get!bool);
                case XPathResultType.number:
                    return value.get!double;
                case XPathResultType.text:
                    return toNumber!S(value.get!S);
                default:
                    assert(0);
            }
        }
        else
        {
            switch (returnType)
            {
                case XPathResultType.boolean:
                    return toText!S(value.get!bool);
                case XPathResultType.number:
                    return toText!S(value.get!double);
                case XPathResultType.text:
                    return value.get!S;
                default:
                    assert(0);
            }
        }
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluate(value: %s)", inputContext.indentString,
                shortClassName, value.toString());
        }

        outputContext.resValue = value;
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.putAttribute(format("::value(%s)", returnType), value.toString());

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.constant;
    }

    final override XPathResultType returnType() const
    {
        return _valueType;
    }

    final Variant value()
    {
        return _value;
    }
}

private void opCompare(string aOp, S)(XPathOperator!S aOpNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    XPathContext!S outputContext1 = inputContext.createOutputContext();
    aOpNode.operand1.evaluate(inputContext, outputContext1);

    XPathContext!S outputContext2 = inputContext.createOutputContext();
    aOpNode.operand2.evaluate(inputContext, outputContext2);

    debug (traceXmlXPathParser)
    {
        import std.stdio : writefln;

        writefln("%s%s.evaluate%s(operand1: %s, nodeListCount1: %d)",
            inputContext.indentString, aOpNode.shortClassName, aOp,
            getShortClassName!S(aOpNode.operand1), outputContext1.resNodes.length);
        writefln("%s%s.evaluate%s(operand2: %s, nodeListCount2: %d)",
            inputContext.indentString, aOpNode.shortClassName, aOp,
            getShortClassName!S(aOpNode.operand2), outputContext2.resNodes.length);
    }

    bool result;
    if (outputContext1.resValue.hasValue && outputContext2.resValue.hasValue)
    {
        Variant v1 = outputContext1.resValue;
        Variant v2 = outputContext2.resValue;
        normalizeValues!S(v1, v2);

        result = mixin("v1 " ~ aOp ~ " v2");
    }
    else if (!outputContext1.resValue.hasValue && !outputContext2.resValue.hasValue)
    {
        for (size_t i = 0; i < outputContext1.resNodes.length; ++i)
        {
            auto e1 = outputContext1.resNodes.item(i);
            S s1 = e1.toText();
            for (size_t j = 0; j < outputContext2.resNodes.length; ++j)
            {
                auto e2 = outputContext2.resNodes.item(j);
                if (mixin("s1 " ~ aOp ~ " e2.toText()"))
                {
                    outputContext.resNodes.insertBack(e1);
                    result = true;
                    break;
                }
            }
        }
    }
    else
    {
        Variant v1 = outputContext1.resValue.hasValue ? outputContext1.resValue : outputContext2.resValue;
        XPathDataType t1 = valueDataType(v1);

        Variant v2;
        bool resultNodeSet = !outputContext1.resNodes.empty;
        XmlNodeList!S nodeList2 = outputContext1.resNodes.empty ? outputContext2.resNodes : outputContext1.resNodes;
        for (size_t i = 0; i < nodeList2.length; ++i)
        {
            auto e2 = nodeList2.item(i);
            v2 = Variant(e2.toText());
            normalizeValueTo!S(v2, t1);

            /*
            debug (traceXmlXPathParser)
            {            
                import std.stdio : writefln;

                writefln("%s%s.evaluate%s(name: %s, value: %s, v1: %s)", 
                    inputContext.indentString, aOpNode.shortClassName, aOp,
                    e2.name, e2.toText(), v1.toString());
            }
            */

            if (mixin("v1 " ~ aOp ~ " v2"))
            {
                result = true;
                if (resultNodeSet)
                    outputContext.resNodes.insertBack(e2);
                else
                    break;
            }
        }
    }

    outputContext.resValue = Variant(result);
}

private void opBinary(string aOp, S)(XPathOperator!S aOpNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double v1 = aOpNode.operand1.get!double(inputContext);
    double v2 = aOpNode.operand2.get!double(inputContext);
    double result;
    if (isNaN(v1) || isNaN(v2))
        result = double.nan;
    else
    {
        static if (aOp == "mod")
        {
            import std.math : fmod;

            result = fmod(v1, v2);
        }
        else
            result = mixin("v1 " ~ aOp ~ " v2");
    }

    outputContext.resValue = Variant(result);
}

class XPathOperator(S) : XPathNode!S
{
protected:
    XPathAstNodeEvaluate evaluateFct;
    XPathNode!S _operand1, _operand2;
    XPathOp _opType;

    final void evaluateAnd(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        bool result = operand1.get!bool(inputContext);
        if (result)
            result = operand2.get!bool(inputContext);

        outputContext.resValue = Variant(result);
    }

    final void evaluateDivide(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("/", S)(this, inputContext, outputContext);
    }

    final void evaluateEq(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("==", S)(this, inputContext, outputContext);
    }

    final void evaluateGe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!(">=", S)(this, inputContext, outputContext);
    }

    final void evaluateGt(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!(">", S)(this, inputContext, outputContext);
    }

    final void evaluateLe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("<=", S)(this, inputContext, outputContext);
    }

    final void evaluateLt(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("<", S)(this, inputContext, outputContext);
    }

    final void evaluateMinus(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("-", S)(this, inputContext, outputContext);
    }

    final void evaluateMod(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("mod", S)(this, inputContext, outputContext);
    }

    final void evaluateMultiply(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("*", S)(this, inputContext, outputContext);
    }

    final void evaluateNe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("!=", S)(this, inputContext, outputContext);
    }

    final void evaluateOr(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        bool result = operand1.get!bool(inputContext);
        if (!result)
            result = operand2.get!bool(inputContext);

        outputContext.resValue = Variant(result);
    }

    final void evaluatePlus(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("+", S)(this, inputContext, outputContext);
    }

    final void evaluateUnion(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        XPathContext!S tempOutputContext1 = inputContext.createOutputContext();
        operand1.evaluate(inputContext, tempOutputContext1);
        for (size_t i = 0; i < tempOutputContext1.resNodes.length; ++i)
        {
            auto e = tempOutputContext1.resNodes.item(i);
            outputContext.resNodes.insertBack(e);
        }

        XPathContext!S tempOutputContext2 = inputContext.createOutputContext();
        operand2.evaluate(inputContext, tempOutputContext2);
        for (size_t i = 0; i < tempOutputContext2.resNodes.length; ++i)
        {
            auto e = tempOutputContext2.resNodes.item(i);
            outputContext.resNodes.insertBack(e);
        }
    }

    final void setEvaluateFct()
    {
        final switch (opType)
        {
            case XPathOp.error:
                evaluateFct = &evaluateError;
                break;
            case XPathOp.and:
                evaluateFct = &evaluateAnd;
                break;
            case XPathOp.or:
                evaluateFct = &evaluateOr;
                break;
            case XPathOp.eq:
                evaluateFct = &evaluateEq;
                break;
            case XPathOp.ne:
                evaluateFct = &evaluateNe;
                break;
            case XPathOp.lt:
                evaluateFct = &evaluateLt;
                break;
            case XPathOp.le:
                evaluateFct = &evaluateLe;
                break;
            case XPathOp.gt:
                evaluateFct = &evaluateGt;
                break;
            case XPathOp.ge:
                evaluateFct = &evaluateGe;
                break;
            case XPathOp.plus:
                evaluateFct = &evaluatePlus;
                break;
            case XPathOp.minus:
                evaluateFct = &evaluateMinus;
                break;
            case XPathOp.multiply:
                evaluateFct = &evaluateMultiply;
                break;
            case XPathOp.divide:
                evaluateFct = &evaluateDivide;
                break;
            case XPathOp.mod:
                evaluateFct = &evaluateMod;
                break;
            case XPathOp.union_:
                evaluateFct = &evaluateUnion;
                break;
        }
    }

public:
    this(XPathNode!S aParent, XPathOp aOpType, XPathNode!S aOperand1, XPathNode!S aOperand2)
    {
        debug (traceXmlXPathParser) 
        {            
            import std.stdio : writefln;

            writefln("%s.this(opType: %s, operand1: %s, operand2: %s)",
                shortClassName, aOpType, getShortClassName!S(aOperand1), getShortClassName!S(aOperand2));
        }

        _parent = aParent;
        _opType = aOpType;
        _operand1 = aOperand1;
        _operand2 = aOperand2;

        setEvaluateFct();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%s%s.evaluate(opType: %s, operand1: %s, operand2: %s, nodeListCount: %d)",
                inputContext.indentString, shortClassName, opType, getShortClassName!S(operand1), getShortClassName!S(operand2),
                inputContext.resNodes.length);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        return evaluateFct(inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write(%s)", shortClassName, opType);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.putAttribute("::opType", to!S(opType));
        aWriter.incNodeLevel();
        operand1.write(aWriter.putLF());
        operand2.write(aWriter.putLF());
        aWriter.decNodeLevel();

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.operator;
    }

    final XPathNode!S operand1()
    {
        return _operand1;
    }

    final XPathNode!S operand2()
    {
        return _operand2;
    }

    final XPathOp opType() const
    {
        return _opType;
    }

    final override XPathResultType returnType() const
    {
        if (opType == XPathOp.error)
            return XPathResultType.error;
        else if (opType <= XPathOp.ge)
            return XPathResultType.boolean;
        else if (opType <= XPathOp.mod)
            return XPathResultType.number;
        else
            return XPathResultType.nodeSet;
    }
}

class XPathRoot(S) : XPathNode!S
{
public:
    this(XPathNode!S aParent)
    {
        debug (traceXmlXPathParser) 
        {            
            import std.stdio : writeln;

            writeln(shortClassName, ".this()");
        }

        _parent = aParent;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluate()", inputContext.indentString, shortClassName);
        }

        outputContext.resNodes.insertBack(inputContext.xpathDocumentElement());
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.root;
    }

    final override XPathResultType returnType() const
    {
        return XPathResultType.nodeSet;
    }
}

class XPathVariable(S) : XPathNode!S
{
public:
    this(XPathNode!S aParent, const(C)[] aPrefix, const(C)[] aLocalName)
    {
        debug (traceXmlXPathParser) 
        {            
            import std.stdio : writefln;

            writefln("%s.this(prefix: %s, localName: %s)", shortClassName, aPrefix, aLocalName);
        }

        _parent = aParent;
        _prefix = prefix;
        _localName = aLocalName;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s%s.evaluate(prefix: %s, localName: %s)",
                inputContext.indentString, shortClassName, prefix, localName);
        }

        Variant* result = qualifiedName() in inputContext.variables;
        if (result is null && prefix.length > 0)
          result = localName.idup in inputContext.variables;

        if (result is null)
            throw new XmlInvalidOperationException(Message.eInvalidVariableName, qualifiedName());
        
        outputContext.resValue = *result;
    }

    final override XmlWriter!S write(XmlWriter!S aWriter)
    {
        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%s.write", this.shortClassName);
        }
        */

        aWriter.putIndent();
        aWriter.put(className);
        aWriter.putAttribute("::name", qualifiedName);

        return aWriter;
    }

@property:
    final override XPathAstType astType() const
    {
        return XPathAstType.variable;
    }

    final const(C)[] localName() const
    {
        return _localName;
    }

    final const(C)[] prefix() const
    {
        return _prefix;
    }

    final override XPathResultType returnType() const
    {
        return XPathResultType.any;
    }
}

class XPathAxisTypeTable(S) : XmlObject!S
{
protected:
    __gshared static XPathAxisTypeTable!S _defaultAxisTypeTable;

    static XPathAxisTypeTable!S createDefaultAxisTypeTable()
    {
        return new XPathAxisTypeTable!S();
    }

protected:
    final void initDefault()
    {
        data["ancestor"] = XPathAxisType.ancestor;
        data["ancestor-or-self"] = XPathAxisType.ancestorOrSelf;
        data["attribute"] = XPathAxisType.attribute;
        data["child"] = XPathAxisType.child;
        data["descendant"] = XPathAxisType.descendant;
        data["descendant-or-self"] = XPathAxisType.descendantOrSelf;
        data["following"] = XPathAxisType.following;
        data["following-sibling"] = XPathAxisType.followingSibling;
        data["namespace"] = XPathAxisType.namespace;
        data["parent"] = XPathAxisType.parent;
        data["preceding"] = XPathAxisType.preceding;
        data["preceding-sibling"] = XPathAxisType.precedingSibling;
        data["self"] = XPathAxisType.self;
        data.rehash();
    }

public:
    XPathAxisType[S] data;

    this()
    {
        initDefault();
    }

    static const(XPathAxisTypeTable!S) defaultAxisTypeTable()
    {
        return singleton!(XPathAxisTypeTable!S)(_defaultAxisTypeTable, &createDefaultAxisTypeTable);
    }

    final XPathAxisType get(const(C)[] aName, XPathAxisType aDefault = XPathAxisType.error) const
    {
        return data.get(aName.idup, aDefault);
    }

    final XPathAxisType get(S aName, XPathAxisType aDefault = XPathAxisType.error) const
    {
        return data.get(aName, aDefault);
    }

    alias data this;
}

class XPathParamInfo(S) : XmlObject!S
{
private:
    const(XPathResultType[]) _argTypes;
    size_t _minArgs, _maxArgs;
    XPathFunctionType _functionType;

public:
    this(XPathFunctionType aFunctionType, size_t aMinArgs, size_t aMaxArgs,
        const(XPathResultType[]) aArgTypes)
    {
        _functionType = aFunctionType;
        _minArgs = aMinArgs;
        _maxArgs = aMaxArgs;
        _argTypes = aArgTypes;
    }

@property:
    final const(XPathResultType[]) argTypes() const
    {
        return _argTypes;
    }

    final XPathFunctionType functionType() const
    {
        return _functionType;
    }

    final size_t maxArgs() const
    {
        return _maxArgs;
    }

    final size_t minArgs() const
    {
        return _minArgs;
    }

    final XPathResultType returnType() const
    {
        return toResultType(_functionType);
    }
}

class XPathFunctionParamInfoTable(S) : XmlObject!S
{
protected:
    __gshared static XPathFunctionParamInfoTable!S _defaultFunctionParamInfoTable;

    static XPathFunctionParamInfoTable!S createDefaultFunctionParamInfoTable()
    {
        return new XPathFunctionParamInfoTable!S();
    }

protected:
    final void initDefault()
    {
        static immutable XPathResultType[] paramTypeEmpty = [];
        static immutable XPathResultType[] paramType1NodeSet = [XPathResultType.nodeSet];
        static immutable XPathResultType[] paramType1Any = [XPathResultType.any];
        static immutable XPathResultType[] paramType1Text = [XPathResultType.text];
        static immutable XPathResultType[] paramType2Text = [XPathResultType.text, XPathResultType.text];
        static immutable XPathResultType[] paramType1Text2Number = [XPathResultType.text, XPathResultType.number, XPathResultType.number];
        static immutable XPathResultType[] paramType3Text = [XPathResultType.text, XPathResultType.text, XPathResultType.text];
        static immutable XPathResultType[] paramType1Boolean = [XPathResultType.boolean];
        static immutable XPathResultType[] paramType1Number = [XPathResultType.number];

        data["last"] = new XPathParamInfo!S(XPathFunctionType.last, 0, 0, paramTypeEmpty);
        data["position"] = new XPathParamInfo!S(XPathFunctionType.position, 0, 0, paramTypeEmpty);
        data["name"] = new XPathParamInfo!S(XPathFunctionType.name, 0, 1, paramType1NodeSet);
        data["namespace-uri"] = new XPathParamInfo!S(XPathFunctionType.namespaceUri, 0, 1, paramType1NodeSet);
        data["local-name"] = new XPathParamInfo!S(XPathFunctionType.localName, 0, 1, paramType1NodeSet);
        data["count"] = new XPathParamInfo!S(XPathFunctionType.count, 1, 1, paramType1NodeSet);
        data["id"] = new XPathParamInfo!S(XPathFunctionType.id, 1, 1, paramType1Any);
        data["string"] = new XPathParamInfo!S(XPathFunctionType.text, 0, 1, paramType1Any);
        data["concat"] = new XPathParamInfo!S(XPathFunctionType.concat, 2, size_t.max, paramType1Text);
        data["starts-with"] = new XPathParamInfo!S(XPathFunctionType.startsWith, 2, 2, paramType2Text);
        data["contains"] = new XPathParamInfo!S(XPathFunctionType.contains, 2, 2, paramType2Text);
        data["substring-before"] = new XPathParamInfo!S(XPathFunctionType.substringBefore, 2, 2, paramType2Text);
        data["substring-after"] = new XPathParamInfo!S(XPathFunctionType.substringAfter, 2, 2, paramType2Text);
        data["substring"] = new XPathParamInfo!S(XPathFunctionType.substring, 2, 3, paramType1Text2Number);
        data["string-length"] = new XPathParamInfo!S(XPathFunctionType.stringLength, 0, 1, paramType1Text);
        data["normalize-space"] = new XPathParamInfo!S(XPathFunctionType.normalize, 0, 1, paramType1Text);
        data["translate"] = new XPathParamInfo!S(XPathFunctionType.translate, 3, 3, paramType3Text);
        data["boolean"] = new XPathParamInfo!S(XPathFunctionType.boolean, 1, 1, paramType1Any);
        data["not"] = new XPathParamInfo!S(XPathFunctionType.not, 1, 1, paramType1Boolean);
        data["true"] = new XPathParamInfo!S(XPathFunctionType.true_, 0, 0, paramType1Boolean);
        data["false"] = new XPathParamInfo!S(XPathFunctionType.false_, 0, 0, paramType1Boolean);
        data["lang"] = new XPathParamInfo!S(XPathFunctionType.lang, 1, 1, paramType1Text);
        data["number"] = new XPathParamInfo!S(XPathFunctionType.number, 0, 1, paramType1Any);
        data["sum"] = new XPathParamInfo!S(XPathFunctionType.sum, 1, 1, paramType1NodeSet);
        data["floor"] = new XPathParamInfo!S(XPathFunctionType.floor, 1, 1, paramType1Number);
        data["ceiling"] = new XPathParamInfo!S(XPathFunctionType.ceiling, 1, 1, paramType1Number);
        data["round"] = new XPathParamInfo!S(XPathFunctionType.round, 1, 1, paramType1Number);
        data.rehash();
    }

public:
    XPathParamInfo!S[S] data;

    this()
    {
        initDefault();
    }

    static const(XPathFunctionParamInfoTable!S) defaultFunctionParamInfoTable()
    {
        return singleton!(XPathFunctionParamInfoTable!S)(_defaultFunctionParamInfoTable, &createDefaultFunctionParamInfoTable);
    }

    final const(XPathParamInfo!S) find(const(C)[] aName) const
    {
        return data.get(aName.idup, null);
    }

    final const(XPathParamInfo!S) find(S aName) const
    {
        return data.get(aName, null);
    }

    alias data this;
}

enum XPathScannerLexKind
{
    comma = ',',
    slash = '/',
    at = '@',
    dot = '.',
    lParens = '(',
    rParens = ')',
    lBracket = '[',
    rBracket = ']',
    star = '*',
    plus = '+',
    minus = '-',
    eq = '=',
    lt = '<',
    gt = '>',
    bang = '!',
    dollar = '$',
    apos = '\'',
    quote = '"',
    union_ = '|',
    ne = 'N', // !=
    le = 'L', // <=
    ge = 'G', // >=
    and = 'A', // &&
    or = 'O', // ||
    dotDot = 'D', // ..
    slashSlash = 'S', // //
    axe = 'a', // Axe (like child::)
    name = 'n', // XML name
    number = 'd', // Number constant
    text = 't', // Quoted string constant
    eof = 'e' // End of string
}

struct XPathScanner(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

private:
    const(C)[] _prefix, _name, _textValue;
    const(C)[] _xPathExpression;
    size_t _xPathExpressionNextIndex, _xPathExpressionLength;
    double _numberValue;
    C _currentChar, _kind;
    bool _canBeFunction;

public:
    this(const(C)[] aXPathExpression)
    {
        assert(aXPathExpression.length > 0);

        _xPathExpression = aXPathExpression;
        _xPathExpressionLength = _xPathExpression.length;
        nextChar();
        nextLex();
    }

    bool nextChar()
    {
        assert(_xPathExpressionNextIndex <= _xPathExpressionLength);

        if (_xPathExpressionNextIndex < _xPathExpressionLength)
        {
            _currentChar = _xPathExpression[_xPathExpressionNextIndex++];
            return true;
        }
        else
        {
            _currentChar = 0;
            return false;
        }
    }

    bool nextLex()
    {
        skipSpace();
        switch (currentChar)
        {
            case '\0':
                _kind = XPathScannerLexKind.eof;
                return false;
            case ',':
            case '@':
            case '(':
            case ')':
            case '|':
            case '*':
            case '[':
            case ']':
            case '+':
            case '-':
            case '=':
            case '#':
            case '$':
                _kind = currentChar;
                nextChar();
                break;
            case '<':
                _kind = XPathScannerLexKind.lt;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.le;
                    nextChar();
                }
                break;
            case '>':
                _kind = XPathScannerLexKind.gt;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.ge;
                    nextChar();
                }
                break;
            case '!':
                _kind = XPathScannerLexKind.bang;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.ne;
                    nextChar();
                }
                break;
            case '.':
                _kind = XPathScannerLexKind.dot;
                nextChar();
                if (currentChar == '.')
                {
                    _kind = XPathScannerLexKind.dotDot;
                    nextChar();
                }
                else if (isDigit(currentChar))
                {
                    _kind = XPathScannerLexKind.number;
                    _numberValue = scanNumberM();
                }
                break;
            case '/':
                _kind = XPathScannerLexKind.slash;
                nextChar();
                if (currentChar == '/')
                {
                    _kind = XPathScannerLexKind.slashSlash;
                    nextChar();
                }
                break;
            case '"':
            case '\'':
                _kind = XPathScannerLexKind.text;
                _textValue = scanText();
                break;
            default:
                if (isDigit(currentChar))
                {
                    _kind = XPathScannerLexKind.number;
                    _numberValue = scanNumberS();
                }
                else if (isNameStartC(currentChar))
                {
                    _kind = XPathScannerLexKind.name;
                    _prefix = null;
                    _name = scanName();
                    // "foo:bar" is one lexem not three because it doesn't allow spaces in between
                    // We should distinct it from "foo::" and need process "foo ::" as well
                    if (currentChar == ':')
                    {
                        nextChar();
                        // can be "foo:bar" or "foo::"
                        if (currentChar == ':')
                        {
                            // "foo::"
                            nextChar();
                            _kind = XPathScannerLexKind.axe;
                        }
                        else
                        {
                            // "foo:*", "foo:bar" or "foo: "
                            _prefix = _name;
                            if (currentChar == '*')
                            {
                                nextChar();
                                _name = "*";
                            }
                            else if (isNameStartC(currentChar))
                                _name = scanName();
                            else
                                throw new XmlParserException(Message.eInvalidNameAtOf,
                                        currentIndex + 1, sourceText);
                        }
                    }
                    else
                    {
                        skipSpace();
                        if (currentChar == ':')
                        {
                            nextChar();
                            // it can be "foo ::" or just "foo :"
                            if (currentChar == ':')
                            {
                                nextChar();
                                _kind = XPathScannerLexKind.axe;
                            }
                            else
                                throw new XmlParserException(Message.eInvalidNameAtOf,
                                        currentIndex + 1, sourceText);
                        }
                    }
                    skipSpace();
                    _canBeFunction = (currentChar == '(');
                }
                else
                    throw new XmlParserException(Message.eInvalidTokenAtOf,
                            currentChar, currentIndex + 1, sourceText);
                break;
        }

        return true;
    }

    const(C)[] scanName()
    {
        assert(isNameStartC(currentChar));
        assert(_xPathExpressionNextIndex >= 1);

        size_t start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;
        while (currentChar != ':' && isNameInC(currentChar))
        {
            ++end;
            nextChar();
        }

        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("scanName(%s [%d .. %d])", _xPathExpression[start .. end], start, end);
        }
        */

        return _xPathExpression[start .. end];
    }

    double scanNumberM()
    {
        assert(isDigit(currentChar));
        assert(_xPathExpressionNextIndex >= 2);

        size_t start = _xPathExpressionNextIndex - 2;
        assert(start >= 0 && _xPathExpression[start] == '.');
        size_t end = _xPathExpressionNextIndex - 1;
        while (isDigit(currentChar))
        {
            ++end;
            nextChar();
        }

        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("scanNumberM(%s [%d .. %d])", _xPathExpression[start .. end], start, end);
        }
        */

        return to!double(_xPathExpression[start .. end]);
    }

    double scanNumberS()
    {
        assert(currentChar == '.' || isDigit(currentChar));
        assert(_xPathExpressionNextIndex >= 1);

        size_t start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;
        while (isDigit(currentChar))
        {
            ++end;
            nextChar();
        }
        if (currentChar == '.')
        {
            ++end;
            nextChar();
            while (isDigit(currentChar))
            {
                ++end;
                nextChar();
            }
        }

        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("scanNumberS(%s [%d .. %d])", _xPathExpression[start .. end], start, end);
        }
        */

        return to!double(_xPathExpression[start .. end]);
    }

    const(C)[] scanText()
    {
        C quoteChar = currentChar;
        nextChar();
        assert(_xPathExpressionNextIndex >= 1);
        size_t start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;
        while (currentChar != quoteChar)
        {
            if (!nextChar())
                throw new XmlParserException(Message.eExpectedCharButEos, quoteChar);
            ++end;
        }
        assert(currentChar == quoteChar);
        nextChar();

        /*
        debug(traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("scanText(%s [%d .. %d])", leftStringIndicator!S(_xPathExpression[start .. end], 30), start, end);
        }
        */

        return _xPathExpression[start .. end];
    }

    void skipSpace()
    {
        while (isSpace(currentChar) && nextChar())
        {
        }
    }

@property:
    bool canBeFunction()
    {
        assert(_kind == XPathScannerLexKind.name);

        return _canBeFunction;
    }

    C currentChar()
    {
        return _currentChar;
    }

    int currentIndex()
    {
        return _xPathExpressionNextIndex - 1;
    }

    bool isNameNodeType()
    {
        auto t = nameNodeType;
        return ((prefix.length == 0) &&
                (t == XPathNodeType.comment ||
                 t == XPathNodeType.all ||
                 t == XPathNodeType.processingInstruction ||
                 t == XPathNodeType.text));
    }

    bool isPrimaryExpr()
    {
        auto k = kind;
        return (k == XPathScannerLexKind.dollar ||
                k == XPathScannerLexKind.lParens ||
                k == XPathScannerLexKind.number ||
                k == XPathScannerLexKind.text ||
                k == XPathScannerLexKind.name
                && canBeFunction && !isNameNodeType);
    }

    bool isStep()
    {
        auto k = kind;
        return (k == XPathScannerLexKind.at ||
                k == XPathScannerLexKind.axe ||
                k == XPathScannerLexKind.dot ||
                k == XPathScannerLexKind.dotDot ||
                k == XPathScannerLexKind.name ||
                k == XPathScannerLexKind.star);
    }

    C kind()
    {
        return _kind;
    }

    const(C)[] name()
    {
        return _name;
    }

    XPathAxisType nameAxisType()
    {
        assert(kind == XPathScannerLexKind.axe);
        assert(_name !is null);

        return XPathAxisTypeTable!S.defaultAxisTypeTable().get(name);
    }

    XPathNodeType nameNodeType()
    {
        assert(_name !is null);

        auto n = name;
        return n == "comment" ? XPathNodeType.comment :
            n == "node" ? XPathNodeType.all :
            n == "processing-instruction" ? XPathNodeType.processingInstruction :
            n == "text" ? XPathNodeType.text :
            XPathNodeType.root;
    }

    double numberValue()
    {
        assert(_kind == XPathScannerLexKind.number);

        return _numberValue;
    }

    const(C)[] prefix()
    {
        assert(_kind == XPathScannerLexKind.name);

        return _prefix;
    }

    const(C)[] sourceText()
    {
        return _xPathExpression;
    }

    const(C)[] textValue()
    {
        assert(_kind == XPathScannerLexKind.text);
        assert(_textValue !is null);

        return _textValue;
    }
}

struct XPathParser(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

private:
    XPathScanner!S scanner;

    // The recursive is like 
    // ParseOrExpr->ParseAndExpr->ParseEqualityExpr->parseRelationalExpr...->parseFilterExpr->parsePredicate->parseExpression
    // So put 200 limitation here will max cause about 2000~3000 depth stack.
    size_t parseDepth;
    enum maxParseDepth = 200;

    debug (traceXmlXPathParser)
    {
        size_t nodeIndent;

        final string indentString()
        {
            return stringOfChar!string(' ', nodeIndent << 1);
        }

        final string traceString(string aMethod, XPathNode!S aInput)
        {
            return format("%s%s(input: %s, scannerName: %s)", indentString(), aMethod,
                getShortClassName!S(aInput), scanner.name);
        }
    }

    pragma(inline, true)
    void checkAndSkipToken(C t)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%spassToken('%c') ? '%c'", indentString(), t, scanner.kind);
        }

        checkToken(t);
        nextLex();
    }

    pragma(inline, true)
    void checkNodeSet(XPathResultType t)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%scheckNodeSet(%d) ? [%d, %d]", indentString(), t,
                XPathResultType.nodeSet, XPathResultType.any);
        }

        if (t != XPathResultType.nodeSet && t != XPathResultType.any)
            throw new XmlParserException(Message.eNodeSetExpectedAtOf,
                    scanner.currentIndex + 1, sourceText);
    }

    pragma(inline, true)
    void checkToken(C t)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%scheckToken('%c') ? '%c'", indentString(), t, scanner.kind);
        }

        if (scanner.kind != t)
            throw new XmlParserException(Message.eInvalidTokenAtOf,
                    scanner.currentChar, scanner.currentIndex + 1, sourceText);
    }

    XPathAxisType getAxisType()
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%sgetAxisType() ? '%s'", indentString(), scanner.name);
        }

        auto axis = scanner.nameAxisType();
        if (axis == XPathAxisType.error)
            throw new XmlParserException(Message.eInvalidTokenAtOf,
                scanner.currentChar, scanner.currentIndex + 1, sourceText);
        return axis;
    }

    pragma(inline, true)
    bool isOp(const(C)[] opName)
    {
        debug (traceXmlXPathParser)
        {            
            import std.stdio : writefln;

            writefln("%stestOp('%s') ? '%s'", indentString(), opName, scanner.name);
        }

        return (scanner.kind == XPathScannerLexKind.name &&
                scanner.prefix.length == 0 &&
                scanner.name == opName);
    }

    pragma(inline, true)
    void nextLex()
    {
        scanner.nextLex();
    }

    XPathNode!S parseExpression(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseExpression", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (++parseDepth > maxParseDepth)
            throw new XmlParserException(Message.eExpressionTooComplex, sourceText);

        XPathNode!S result = parseOrExpr(aInput);
        --parseDepth;
        return result;
    }

    // OrExpr ::= ( OrExpr 'or' )? AndExpr 
    XPathNode!S parseOrExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseOrExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseAndExpr(aInput);

        do
        {
            if (!isOp("or"))
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.or, result, parseAndExpr(aInput));
        }
        while (true);
    }

    // AndExpr ::= ( AndExpr 'and' )? EqualityExpr 
    XPathNode!S parseAndExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseAndExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseEqualityExpr(aInput);

        do
        {
            if (!isOp("and"))
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.and, result, parseEqualityExpr(aInput));
        }
        while (true);
    }

    // EqualityOp ::= '=' | '!='
    // EqualityExpr ::= ( EqualityExpr EqualityOp )? RelationalExpr
    XPathNode!S parseEqualityExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseEqualityExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseRelationalExpr(aInput);

        do
        {
            XPathOp op = scanner.kind == XPathScannerLexKind.eq ? XPathOp.eq :
                scanner.kind == XPathScannerLexKind.ne ? XPathOp.ne :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseRelationalExpr(aInput));
        }
        while (true);
    }

    // RelationalOp ::= '<' | '>' | '<=' | '>='
    // RelationalExpr ::= ( RelationalExpr RelationalOp )? AdditiveExpr  
    XPathNode!S parseRelationalExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseRelationalExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseAdditiveExpr(aInput);

        do
        {
            XPathOp op = scanner.kind == XPathScannerLexKind.lt ? XPathOp.lt :
                scanner.kind == XPathScannerLexKind.le ? XPathOp.le :
                scanner.kind == XPathScannerLexKind.gt ? XPathOp.gt :
                scanner.kind == XPathScannerLexKind.ge ? XPathOp.ge :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseAdditiveExpr(aInput));
        }
        while (true);
    }

    // AdditiveOp ::= '+' | '-'
    // AdditiveExpr ::= ( AdditiveExpr AdditiveOp )? MultiplicativeExpr
    XPathNode!S parseAdditiveExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseAdditiveExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseMultiplicativeExpr(aInput);

        do
        {
            XPathOp op = scanner.kind == XPathScannerLexKind.plus ? XPathOp.plus :
                scanner.kind == XPathScannerLexKind.minus ? XPathOp.minus :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseMultiplicativeExpr(aInput));
        }
        while (true);
    }

    // MultiplicativeOp ::= '*' | 'div' | 'mod'
    // MultiplicativeExpr ::= ( MultiplicativeExpr MultiplicativeOp )? UnaryExpr
    XPathNode!S parseMultiplicativeExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseMultiplicativeExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseUnaryExpr(aInput);

        do
        {
            XPathOp op = scanner.kind == XPathScannerLexKind.star ? XPathOp.multiply :
                isOp("div") ? XPathOp.divide :
                isOp("mod") ? XPathOp.mod :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseUnaryExpr(aInput));
        }
        while (true);
    }

    // UnaryExpr ::= UnionExpr | '-' UnaryExpr
    XPathNode!S parseUnaryExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseUnaryExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        bool minus;
        while (scanner.kind == XPathScannerLexKind.minus)
        {
            nextLex();
            minus = !minus;
        }

        if (minus)
            return new XPathOperator!S(aInput, XPathOp.multiply,
                    parseUnionExpr(aInput), new XPathOperand!S(aInput, -1.0));
        else
            return parseUnionExpr(aInput);
    }

    // UnionExpr ::= ( UnionExpr '|' )? PathExpr  
    XPathNode!S parseUnionExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseUnionExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parsePathExpr(aInput);

        do
        {
            if (scanner.kind != XPathScannerLexKind.union_)
                return result;
            checkNodeSet(result.returnType);

            nextLex();
            XPathNode!S opnd2 = parsePathExpr(aInput);
            checkNodeSet(opnd2.returnType);

            result = new XPathOperator!S(result, XPathOp.union_, result, opnd2);
        }
        while (true);
    }

    // PathOp ::= '/' | '//'
    // PathExpr ::= LocationPath | FilterExpr ( PathOp  RelativeLocationPath )?
    XPathNode!S parsePathExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parsePathExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        if (scanner.isPrimaryExpr())
        {
            // in this moment we should distinct LocationPas vs FilterExpr 
            // (which starts from is PrimaryExpr)
            result = parseFilterExpr(aInput);
            if (scanner.kind == XPathScannerLexKind.slash)
            {
                nextLex();
                result = parseRelativeLocationPath(result);
            }
            else if (scanner.kind == XPathScannerLexKind.slashSlash)
            {
                nextLex();
                result = parseRelativeLocationPath(new XPathAxis!S(result,
                        XPathAxisType.descendantOrSelf, result));
            }
        }
        else
            result = parseLocationPath(null); // Must pass null 

        return result;
    }

    // FilterExpr ::= PrimaryExpr | FilterExpr Predicate 
    XPathNode!S parseFilterExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseFilterExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parsePrimaryExpr(aInput);
        while (scanner.kind == XPathScannerLexKind.lBracket) // result must be a query
            result = new XPathFilter!S(result, result, parsePredicate(result));

        return result;
    }

    // Predicate ::= '[' Expr ']'
    XPathNode!S parsePredicate(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parsePredicate", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // we have predicates. Check that input type is NodeSet
        checkNodeSet(aInput.returnType);

        checkAndSkipToken(XPathScannerLexKind.lBracket);
        XPathNode!S result = parseExpression(aInput);
        checkAndSkipToken(XPathScannerLexKind.rBracket);

        return result;
    }

    // LocationPath ::= RelativeLocationPath | AbsoluteLocationPath
    XPathNode!S parseLocationPath(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseLocationPath", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (scanner.kind == XPathScannerLexKind.slash)
        {
            nextLex();
            XPathNode!S result = new XPathRoot!S(aInput);

            if (scanner.isStep)
                result = parseRelativeLocationPath(result);

            return result;
        }
        else if (scanner.kind == XPathScannerLexKind.slashSlash)
        {
            nextLex();
            return parseRelativeLocationPath(new XPathAxis!S(aInput,
                    XPathAxisType.descendantOrSelf, new XPathRoot!S(aInput)));
        }
        else
            return parseRelativeLocationPath(aInput);
    }

    // Pattern ::= ( Pattern '|' )? LocationPathPattern
    XPathNode!S parsePattern(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parsePattern", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseLocationPathPattern(aInput);

        do
        {
            if (scanner.kind != XPathScannerLexKind.union_)
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.union_, result,
                    parseLocationPathPattern(result));
        }
        while (true);
    }

    // PathOp ::= '/' | '//'
    // RelativeLocationPath ::= ( RelativeLocationPath PathOp )? Step 
    XPathNode!S parseRelativeLocationPath(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseRelativeLocationPath", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = aInput;
        do
        {
            result = parseStep(result);
            if (XPathScannerLexKind.slashSlash == scanner.kind)
            {
                nextLex();
                result = new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result);
            }
            else if (XPathScannerLexKind.slash == scanner.kind)
                nextLex();
            else
                break;
        }
        while (true);

        return result;
    }

    // Step ::= '.' | '..' | ( AxisName '::' | '@' )? NodeTest Predicate*
    XPathNode!S parseStep(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseStep", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        if (XPathScannerLexKind.dot == scanner.kind)
        {
            // '.'
            nextLex();
            result = new XPathAxis!S(aInput, XPathAxisType.self, aInput);
        }
        else if (XPathScannerLexKind.dotDot == scanner.kind)
        {
            // '..'
            nextLex();
            result = new XPathAxis!S(aInput, XPathAxisType.parent, aInput);
        }
        else
        {
            // ( AxisName '::' | '@' )? NodeTest Predicate*
            XPathAxisType axisType = XPathAxisType.child;
            switch (scanner.kind)
            {
                case XPathScannerLexKind.at: // '@'
                    axisType = XPathAxisType.attribute;
                    nextLex();
                    break;
                case XPathScannerLexKind.axe: // AxisName '::'
                    axisType = getAxisType();
                    nextLex();
                    break;
                default:
                    break;
            }

            // Need to check for axisType == XPathAxisType.namespace?
            XPathNodeType nodeType = axisType == XPathAxisType.attribute ?
                XPathNodeType.attribute : XPathNodeType.element;

            result = parseNodeTest(aInput, axisType, nodeType);

            while (XPathScannerLexKind.lBracket == scanner.kind)
                result = new XPathFilter!S(result, result, parsePredicate(result));
        }
        return result;
    }

    // NodeTest ::= NameTest | 'comment ()' | 'text ()' | 'node ()' | 'processing-instruction ('  Literal ? ')'
    XPathNode!S parseNodeTest(XPathNode!S aInput, XPathAxisType axisType, XPathNodeType nodeType)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseNodeTest", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] nodeName, nodePrefix;

        switch (scanner.kind)
        {
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction && scanner.isNameNodeType)
                {
                    nodePrefix = null;
                    nodeName = null;
                    nodeType = scanner.nameNodeType;
                    assert(nodeType != XPathNodeType.root);
                    nextLex();

                    checkAndSkipToken(XPathScannerLexKind.lParens);

                    if (nodeType == XPathNodeType.processingInstruction)
                    {
                        if (scanner.kind != XPathScannerLexKind.rParens)
                        {
                            // 'processing-instruction (' Literal ')'
                            checkToken(XPathScannerLexKind.text);
                            nodeName = scanner.textValue;
                            nextLex();
                        }
                    }

                    checkAndSkipToken(XPathScannerLexKind.rParens);
                }
                else
                {
                    nodePrefix = scanner.prefix;
                    nodeName = scanner.name;
                    nextLex();
                }
                break;
            case XPathScannerLexKind.star:
                nodePrefix = null;
                nodeName = "*";
                nextLex();
                break;
            default:
                throw new XmlParserException(Message.eNodeSetExpectedAtOf,
                        scanner.currentIndex + 1, sourceText);
        }

        return new XPathAxis!S(aInput, axisType, aInput, nodeType, nodePrefix, nodeName);
    }

    // PrimaryExpr ::= Literal | Number | VariableReference | '(' Expr ')' | FunctionCall
    XPathNode!S parsePrimaryExpr(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parsePrimaryExpr", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        assert(scanner.isPrimaryExpr);

        XPathNode!S result;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.text:
                result = new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                break;
            case XPathScannerLexKind.number:
                result = new XPathOperand!S(aInput, scanner.numberValue);
                nextLex();
                break;
            case XPathScannerLexKind.dollar:
                nextLex();
                checkToken(XPathScannerLexKind.name);
                result = new XPathVariable!S(aInput, scanner.name, scanner.prefix);
                nextLex();
                break;
            case XPathScannerLexKind.lParens:
                nextLex();
                result = parseExpression(aInput);
                if (result.returnType != XPathAstType.constant)
                    result = new XPathGroup!S(result, result);
                checkAndSkipToken(XPathScannerLexKind.rParens);
                break;
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction && !scanner.isNameNodeType)
                    result = parseMethod(null);
                break;
            default:
                break;
        }

        assert(result !is null, "isPrimaryExpr() was true. We should recognize this lex.");

        return result;
    }

    XPathNode!S parseMethod(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseMethod", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] name = scanner.name;
        const(C)[] prefix = scanner.prefix;
        XPathNode!S[] argList;
        checkAndSkipToken(XPathScannerLexKind.name);

        checkAndSkipToken(XPathScannerLexKind.lParens);
        if (scanner.kind != XPathScannerLexKind.rParens)
        {
            do
            {
                argList ~= parseExpression(aInput);
                if (scanner.kind == XPathScannerLexKind.rParens)
                    break;
                checkAndSkipToken(XPathScannerLexKind.comma);
            }
            while (true);
        }
        checkAndSkipToken(XPathScannerLexKind.rParens);

        if (prefix.length == 0)
        {
            const XPathParamInfo!S pi = XPathFunctionParamInfoTable!S.defaultFunctionParamInfoTable().find(name);
            if (pi !is null)
            {
                if (argList.length < pi.minArgs)
                    throw new XmlParserException(Message.eInvalidNumberArgsOf,
                            argList.length, pi.minArgs, name, sourceText);

                if (pi.functionType == XPathFunctionType.concat)
                {
                    foreach (i, a; argList)
                    {
                        if (a.returnType != XPathResultType.text)
                            argList[i] = new XPathFunction!S(aInput, XPathFunctionType.text, a);
                    }
                }
                else
                {
                    auto argCount = argList.length;
                    if (argCount > pi.maxArgs)
                        throw new XmlParserException(Message.eInvalidNumberArgsOf,
                                argCount, pi.maxArgs, name, sourceText);

                    // argument we have the type specified (can be < pi.minArgs)
                    if (argCount > pi.argTypes.length)
                        argCount = pi.argTypes.length;

                    for (size_t i = 0; i < argCount; ++i)
                    {
                        auto a = argList[i];
                        if (pi.argTypes[i] != XPathResultType.any && pi.argTypes[i] != a.returnType)
                        {
                            switch (pi.argTypes[i])
                            {
                                case XPathResultType.boolean:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.boolean, a);
                                    break;
                                case XPathResultType.nodeSet:
                                    if (!isClassType!(XPathVariable!S)(a) &&
                                        !(isClassType!(XPathFunction!S)(a) &&
                                        a.returnType == XPathResultType.any))
                                        throw new XmlParserException(Message.eInvalidArgTypeOf,
                                                i, name, sourceText);
                                    break;
                                case XPathResultType.number:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.number, a);
                                    break;
                                case XPathResultType.text:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.text, a);
                                    break;
                                default:
                                    break;
                            }
                        }
                    }
                }

                return new XPathFunction!S(aInput, pi.functionType, argList);
            }
        }

        return new XPathFunction!S(aInput, prefix, name, argList);
    }

    // LocationPathPattern ::= '/' | RelativePathPattern | '//' RelativePathPattern | 
    //  '/' RelativePathPattern |
    //  IdKeyPattern (('/' | '//') RelativePathPattern)?  
    XPathNode!S parseLocationPathPattern(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseLocationPathPattern", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.slash:
                nextLex();
                result = new XPathRoot!S(aInput);
                if (scanner.kind == XPathScannerLexKind.eof ||
                    scanner.kind == XPathScannerLexKind.union_)
                    return result;
                break;
            case XPathScannerLexKind.slashSlash:
                nextLex();
                result = new XPathAxis!S(aInput, XPathAxisType.descendantOrSelf, new XPathRoot!S(aInput));
                break;
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction)
                {
                    result = parseIdKeyPattern(aInput);
                    if (result !is null)
                    {
                        switch (scanner.kind)
                        {
                        case XPathScannerLexKind.slash:
                            nextLex();
                            break;
                        case XPathScannerLexKind.slashSlash:
                            nextLex();
                            result = new XPathAxis!S(aInput, XPathAxisType.descendantOrSelf, result);
                            break;
                        default:
                            return result;
                        }
                    }
                }
                break;
            default:
                break;
        }

        return parseRelativePathPattern(result);
    }

    // IdKeyPattern ::= 'id' '(' Literal ')' | 'key' '(' Literal ',' Literal ')'  
    XPathNode!S parseIdKeyPattern(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseIdKeyPattern", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        assert(scanner.canBeFunction);

        XPathNode!S[] argList;
        if (scanner.prefix.length == 0)
        {
            if (scanner.name == "id")
            {
                const XPathParamInfo!S pi = XPathFunctionParamInfoTable!S.defaultFunctionParamInfoTable().find("id");
                assert(pi !is null);

                nextLex();
                checkAndSkipToken(XPathScannerLexKind.lParens);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.rParens);
                return new XPathFunction!S(aInput, pi.functionType, argList);
            }

            if (scanner.name == "key")
            {
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.lParens);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.comma);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.rParens);
                return new XPathFunction!S(aInput, null, "key", argList);
            }
        }

        return null;
    }

    // PathOp ::= '/' | '//'
    // RelativePathPattern ::= ( RelativePathPattern PathOp )? StepPattern
    XPathNode!S parseRelativePathPattern(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseRelativePathPattern", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseStepPattern(aInput);
        if (XPathScannerLexKind.slashSlash == scanner.kind)
        {
            nextLex();
            result = parseRelativePathPattern(new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result));
        }
        else if (XPathScannerLexKind.slash == scanner.kind)
        {
            nextLex();
            result = parseRelativePathPattern(result);
        }
        return result;
    }

    // StepPattern ::= ChildOrAttributeAxisSpecifier NodeTest Predicate*   
    // ChildOrAttributeAxisSpecifier ::= @ ? | ('child' | 'attribute') '::' 
    XPathNode!S parseStepPattern(XPathNode!S aInput)
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writeln;

            writeln(traceString("parseStepPattern", aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathAxisType axisType = XPathAxisType.child;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.at: // '@'
                axisType = XPathAxisType.attribute;
                nextLex();
                break;
            case XPathScannerLexKind.axe: // AxisName '::'
                axisType = getAxisType();
                if (axisType != XPathAxisType.child && axisType != XPathAxisType.attribute)
                    throw new XmlParserException(Message.eInvalidTokenAtOf,
                            scanner.currentChar, scanner.currentIndex + 1, sourceText);
                nextLex();
                break;
            default:
                break;
        }

        XPathNodeType nodeType = axisType == XPathAxisType.attribute ?
            XPathNodeType.attribute : XPathNodeType.element;

        XPathNode!S result = parseNodeTest(aInput, axisType, nodeType);

        while (XPathScannerLexKind.lBracket == scanner.kind)
            result = new XPathFilter!S(result, result, parsePredicate(result));

        return result;
    }

public:
    this(const(C)[] aXPathExpressionOrPattern)
    {
        scanner = XPathScanner!S(aXPathExpressionOrPattern);
    }

    XPathNode!S parseExpression()
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%sparseExpression(%s)", indentString(), sourceText);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseExpression(null);
        if (scanner.kind != XPathScannerLexKind.eof)
            throw new XmlParserException(Message.eInvalidTokenAtOf,
                    scanner.currentChar, scanner.currentIndex + 1, sourceText);
        return result;
    }

    XPathNode!S parsePattern()
    {
        debug (traceXmlXPathParser)
        {
            import std.stdio : writefln;

            writefln("%sparsePattern(%s)", indentString(), sourceText);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parsePattern(null);
        if (scanner.kind != XPathScannerLexKind.eof)
            throw new XmlParserException(Message.eInvalidTokenAtOf,
                    scanner.currentChar, scanner.currentIndex + 1, sourceText);
        return result;
    }

@property:
    const(C)[] sourceText()
    {
        return scanner.sourceText;
    }
}

XmlNodeList!S selectNodes(S)(XmlNode!S aSource, S xpath)
{
    XPathParser!S xpathParser = XPathParser!S(xpath);
    XPathNode!S xpathNode = xpathParser.parseExpression();

    debug (traceXmlXPathParser)
    {
        import std.stdio : writeln;

        writeln("\n", xpath);
        writeln(xpathNode.toString(), "\n");
    }

    XPathContext!S inputContext = XPathContext!S(aSource);

    inputContext.resNodes.insertBack(aSource);

    XPathContext!S outputContext = inputContext.createOutputContext();

    xpathNode.evaluate(inputContext, outputContext);

    return outputContext.resNodes;
}

XmlNode!S selectSingleNode(S)(XmlNode!S aSource, S xpath)
{
    XmlNodeList!S resultList = selectNodes(aSource, xpath);
    return resultList.empty ? null : resultList.front;
}

unittest  // XPathParser
{
    import std.file : write; // write parser tracer info to file

    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XPathParser");
    }

    string[] output;
    XPathParser!string xpathParser;

    string getOutput()
    {
        string s = output[0];
        foreach (e; output[1 .. $])
            s ~= "\n" ~ e;
        return s;
    }

    void toOutput(XPathNode!string r)
    {
        output ~= xpathParser.sourceText.idup;
        output ~= r.toString();
        output ~= "\n";
    }

    xpathParser = XPathParser!string("count(/restaurant/tables/table)");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[1]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title[@lang='eng']");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//title[@lang='eng']");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore//title[@lang]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[3]/*");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore//book[title=\"Harry Potter\"]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[1]/title/@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title/@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//book//@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("./title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("book[last()]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("book/author[last()]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("(book/author)[last()]");
    toOutput(xpathParser.parseExpression());

    //xpathParser = XPathParser!string("degree[position() &lt; 3]");
    xpathParser = XPathParser!string("degree[position() < 3]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("x/y[position() = 1]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("id('foo')");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("id('foo')/child::para[position()=5]");
    toOutput(xpathParser.parseExpression());

    write("xpath_parser_ast.log", getOutput);
}

unittest  // XPathParser.selectNodes
{
    if (outputXmlTraceProgress)
    {
        import std.stdio : writeln;

        writeln("unittest XPathParser.selectNodes");
    }

    static immutable string xml = q"XML
<?xml version="1.0"?>
<!-- A fragment of a book store inventory database -->
<bookstore xmlns:bk="urn:samples">
  <book genre="novel" publicationdate="1997" bk:ISBN="1-861001-57-8">
    <title>Pride And Prejudice</title>
    <author>
      <first-name>Jane</first-name>
      <last-name>Austen</last-name>
    </author>
    <price>24.95</price>
  </book>
  <book genre="novel" publicationdate="1992" bk:ISBN="1-861002-30-1">
    <title>The Handmaid's Tale</title>
    <author>
      <first-name>Margaret</first-name>
      <last-name>Atwood</last-name>
    </author>
    <price>29.95</price>
  </book>
  <book genre="novel" publicationdate="1991" bk:ISBN="1-861001-57-6">
    <title>Emma</title>
    <author>
      <first-name>Jane</first-name>
      <last-name>Austen</last-name>
    </author>
    <price>19.95</price>
  </book>
  <book genre="novel" publicationdate="1982" bk:ISBN="1-861001-45-3">
    <title>Sense and Sensibility</title>
    <author>
      <first-name>Jane</first-name>
      <last-name>Austen</last-name>
    </author>
    <price>19.95</price>
  </book>
</bookstore>
XML";

    auto doc = new XmlDocument!string().load(xml);
    XmlNodeList!string nodeList;
    
    nodeList = doc.documentElement.selectNodes("descendant::book[author/last-name='Austen']");
    assert(nodeList.length == 3);
    assert(nodeList.front.getAttribute("publicationdate") == "1997");
    assert(nodeList.moveFront.name == "book");
    assert(nodeList.front.getAttribute("publicationdate") == "1991");
    assert(nodeList.moveFront.name == "book");
    assert(nodeList.front.getAttribute("publicationdate") == "1982");
    assert(nodeList.moveFront.name == "book");

    
    //writeln("nodeList.length: ", nodeList.length);
    //foreach (e; nodeList)
    //    writeln("nodeName: ", e.name, ", position: ", e.position);
}