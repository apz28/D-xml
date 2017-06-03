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
 
module pham.xml_msg;

struct Message
{
    static immutable eBlankName = "Name is blank";
    static immutable eEos = "Incompleted xml data";
    static immutable eExpectedCharButChar = "Expect character \"%c\" but found \"%c\"";
    static immutable eExpectedCharButEos = "Expect character \"%c\" but incompleted data";
    static immutable eExpectedEndName = "Expect end element name \"%s\" but found \"%s\"";
    static immutable eExpectedStringButEos = "Expect string \"%s\" but incompleted data";
    static immutable eExpectedStringButNotFound = "Expect string \"%s\" but not found";
    static immutable eExpectedStringButString = "Expect string \"%s\" but found \"%s\"";
    static immutable eExpectedOneOfCharsButChar = "Expect one of characters \"%s\" but found \"%c\"";
    static immutable eExpectedOneOfCharsButEos = "Expect one of characters \"%s\" but incompleted data";
    static immutable eExpectedOneOfStringsButString = "Expect one of \"%s\" but found \"%s\"";
    static immutable eInvalidArgTypeOf = "Invalid argument type at \"%d\" for %s; data \"%s\"";
    static immutable eInvalidName = "Invalid name \"%s\"";
    static immutable eInvalidNameAtOf = "Invalid name at \"%d\"; data \"%s\"";
    //static immutable eInvalidNumArgs = "Invalid number of arguments \"%d/%d\" of %s";
    static immutable eInvalidNumberArgsOf = "Invalid number of arguments \"%d\" [expected %d] for %s; data \"%s\"";
    static immutable eInvalidOpDelegate = "Invalid operation %s.%s";
    static immutable eInvalidOpFunction = "Invalid operation %s";
    static immutable eInvalidOpFromWrongParent = "Invalid operation %s.%s of different parent node";
    static immutable eInvalidTokenAtOf = "Invalid token \"%c\" at \"%d\"; data \"%s\"";
    static immutable eInvalidTypeValueOf2 = "Invalid %s value [%s, %s]: \"%s\"";
    static immutable eInvalidUtf8Sequence1 = "Invalid utf8 sequence - end of stream";
    static immutable eInvalidUtf8Sequence2 = "Invalid utf8 sequence - invalid code";
    static immutable eInvalidUtf16Sequence1 = "Invalid utf16 sequence - end of stream";
    static immutable eInvalidUtf16Sequence2 = "Invalid utf16 sequence - invalid code";
    static immutable eInvalidVariableName = "Invalid variable name \"%s\"";
    static immutable eInvalidVersionStr = "Invalid version string \"%s\"";
    static immutable eMultipleTextFound = "Multiple \"%s\" found";
    static immutable eNodeSetExpectedAtOf = "NodeSet is expected at \"%d\"; data \"%s\"";
    static immutable eNotAllWhitespaces = "Not all whitespace characters";
    static immutable eNotAllowChild = "Invalid operation %s.%s. \"%s\" [node type \"%d\"] not allow child \"%s\" [node type \"%d\"]";
    static immutable eNotAllowAppendDifDoc = "Not allow appending \"%s\" with different owner document";
    static immutable eNotAllowAppendSelf = "Not allow appending self as child";
    static immutable eAttributeDuplicated = "Not allow to append duplicated attribute \"%s\"";
    static immutable eAttributeListChanged = "Attribute list had changed since start enumerated";
    static immutable eChildListChanged = "Child list had changed since start enumerated";
    static immutable eExpressionTooComplex = "Expression is too complex \"%s\"";
    static immutable eUnescapeAndChar = "Unescaped \"&\" character";

    static immutable atLineInfo = " at line %d position %d";
}

struct XmlConst
{
    static immutable cDataSectionTagName = "#cdata-section";
    static immutable commentTagName = "#comment";
    static immutable declarationTagName = "xml";
    static immutable documentFragmentTagName = "#document-fragment";
    static immutable documentTagName = "#document";
    //static immutable entityTagName = "#entity";
    //static immutable notationTagName = "#notation";
    static immutable significantWhitespaceTagName = "#significant-whitespace";
    static immutable textTagName = "#text";
    static immutable whitespaceTagName = "#whitespace";

    static immutable declarationEncodingName = "encoding";
    static immutable declarationStandaloneName = "standalone";
    static immutable declarationVersionName = "version";

    static immutable sTrue = "true";
    static immutable sFalse = "false";

    static immutable yes = "yes";
    static immutable no = "no";

    static immutable any = "ANY";
    static immutable empty = "EMPTY";

    static immutable fixed = "#FIXED";
    static immutable implied = "#IMPLIED";
    static immutable required = "#REQUIRED";

    static immutable nData = "NDATA";

    static immutable notation = "NOTATION";
    static immutable public_ = "PUBLIC";
    static immutable system = "SYSTEM";

    static immutable xml = "xml";
    static immutable xmlNS = "http://www.w3.org/XML/1998/namespace";
    static immutable xmlns = "xmlns";
    static immutable xmlnsNS = "http://www.w3.org/2000/xmlns/";
}
