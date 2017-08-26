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

module pham.xml;

import std.typecons : No, Yes;

public import pham.xml_exception;
public import pham.xml_enum;
public import pham.xml_util;
public import pham.xml_buffer;
public import pham.xml_string;
public import pham.xml_entity_table;
public import pham.xml_new;
public import pham.xml_parser;
public import pham.xml_reader;
public import pham.xml_writer;
public import pham.xml_xpath;


/** For utf8 encoded string
*/
alias XmlAttributeA = XmlAttribute!string;
alias XmlCDataA = XmlCData!string;
alias XmlCommentA = XmlComment!string;
alias XmlDeclarationA = XmlDeclaration!string;
alias XmlDocumentA = XmlDocument!string;
alias XmlDocumentTypeA = XmlDocumentType!string;
alias XmlDocumentTypeAttributeListA = XmlDocumentTypeAttributeList!string;
alias XmlDocumentTypeAttributeListDefA = XmlDocumentTypeAttributeListDef!string;
alias XmlDocumentTypeAttributeListDefTypeA = XmlDocumentTypeAttributeListDefType!string;
alias XmlDocumentTypeElementA = XmlDocumentTypeElement!string;
alias XmlDocumentTypeElementItemA = XmlDocumentTypeElementItem!string;
alias XmlElementA = XmlElement!string;
alias XmlEntityA = XmlEntity!string;
alias XmlEntityReferenceA = .XmlEntityReference!string;
alias XmlEntityTableA = XmlEntityTable!string;
alias XmlNameA = XmlName!string;
alias XmlNodeA = XmlNode!string;
alias XmlNodeListA = XmlNodeList!string;
alias XmlNotationA = XmlNotation!string;
alias XmlProcessingInstructionA = XmlProcessingInstruction!string;
alias XmlSignificantWhitespaceA = XmlSignificantWhitespace!string;
alias XmlTextA = XmlText!string;
alias XmlWhitespaceA = XmlWhitespace!string;

alias XmlFileReaderA = XmlFileReader!string;
alias XmlStringReaderA = XmlStringReader!string;

alias XmlFileWriterA = XmlFileWriter!string;
alias XmlStringWriterA = XmlStringWriter!string;

alias selectNodesA = selectNodes!string;
alias selectSingleNodeA = selectSingleNode!string;

/** For utf16 encoded string
*/
alias XmlAttributeW = XmlAttribute!wstring;
alias XmlCDataW = XmlCData!wstring;
alias XmlCommentW = XmlComment!wstring;
alias XmlDeclarationW = XmlDeclaration!wstring;
alias XmlDocumentW = XmlDocument!wstring;
alias XmlDocumentTypeW = XmlDocumentType!wstring;
alias XmlDocumentTypeAttributeListW = XmlDocumentTypeAttributeList!wstring;
alias XmlDocumentTypeAttributeListDefW = XmlDocumentTypeAttributeListDef!wstring;
alias XmlDocumentTypeAttributeListDefTypeW = XmlDocumentTypeAttributeListDefType!wstring;
alias XmlDocumentTypeElementW = XmlDocumentTypeElement!wstring;
alias XmlDocumentTypeElementItemW = XmlDocumentTypeElementItem!wstring;
alias XmlElementW = XmlElement!wstring;
alias XmlEntityW = XmlEntity!wstring;
alias XmlEntityReferenceW = XmlEntityReference!wstring;
alias XmlEntityTableW = XmlEntityTable!wstring;
alias XmlNameW = XmlName!wstring;
alias XmlNodeW = XmlNode!wstring;
alias XmlNodeListW = XmlNodeList!wstring;
alias XmlNotationW = XmlNotation!wstring;
alias XmlProcessingInstructionW = XmlProcessingInstruction!wstring;
alias XmlSignificantWhitespaceW = XmlSignificantWhitespace!wstring;
alias XmlTextW = XmlText!wstring;
alias XmlWhitespaceW = XmlWhitespace!wstring;

alias XmlFileReaderW = XmlFileReader!wstring;
alias XmlStringReaderW = XmlStringReader!wstring;

alias XmlFileWriterW = XmlFileWriter!wstring;
alias XmlStringWriterW = XmlStringWriter!wstring;

alias selectNodesW = selectNodes!wstring;
alias selectSingleNodeW = selectSingleNode!wstring;

/** For utf32 encoded string
*/
alias XmlAttributeD = XmlAttribute!dstring;
alias XmlCDataD = XmlCData!dstring;
alias XmlCommentD = XmlComment!dstring;
alias XmlDeclarationD = XmlDeclaration!dstring;
alias XmlDocumentD = XmlDocument!dstring;
alias XmlDocumentTypeD = XmlDocumentType!dstring;
alias XmlDocumentTypeAttributeListD = XmlDocumentTypeAttributeList!dstring;
alias XmlDocumentTypeAttributeListDefD = XmlDocumentTypeAttributeListDef!dstring;
alias XmlDocumentTypeAttributeListDefTypeD = XmlDocumentTypeAttributeListDefType!dstring;
alias XmlDocumentTypeElementD = XmlDocumentTypeElement!dstring;
alias XmlDocumentTypeElementItemD = XmlDocumentTypeElementItem!dstring;
alias XmlElementD = XmlElement!dstring;
alias XmlEntityD = XmlEntity!dstring;
alias XmlEntityReferenceD = XmlEntityReference!dstring;
alias XmlEntityTableD = XmlEntityTable!dstring;
alias XmlNameD = XmlName!dstring;
alias XmlNodeD = XmlNode!dstring;
alias XmlNodeListD = XmlNodeList!dstring;
alias XmlNotationD = XmlNotation!dstring;
alias XmlProcessingInstructionD = XmlProcessingInstruction!dstring;
alias XmlSignificantWhitespaceD = XmlSignificantWhitespace!dstring;
alias XmlTextD = XmlText!dstring;
alias XmlWhitespaceD = XmlWhitespace!dstring;

alias XmlFileReaderD = XmlFileReader!dstring;
alias XmlStringReaderD = XmlStringReader!dstring;

alias XmlFileWriterD = XmlFileWriter!dstring;
alias XmlStringWriterD = XmlStringWriter!dstring;

alias selectNodesD = selectNodes!dstring;
alias selectSingleNodeD = selectSingleNode!dstring;
