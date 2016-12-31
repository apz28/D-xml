# dlang-xml


XML DOM Implementation for DLang


Boost Software License - Version 1.0


This is my first package written in D. Just discovered D few months ago and this is a great way of learning it.


Some features in this implementation

1. Supports different encodings (char, wchar & dchar)

2. SAX parsing with parent node tracking

3. Can be filtered nodes while loading

4. Pretty output

5. XPath (selectNodes, selectSingleNode)

6. Support custom entity

7. Compare to current phobo\std.xml -> less memory used and twice as fast with validation while parsing


Still lacking document but you can read it from below link if the function name matched

https://msdn.microsoft.com/en-us/library/system.xml.xmlnode(v=vs.110).aspx


Look in unittest section for varius samples on how to use this package


Sample usages


1. Load xml from utf-8 encoded string

import pham.xml_new;

auto doc = new XmlDocument!string().load(xml);


2. Get xml string from a document

string xml = doc.outerXml();

or

import std.typecons : Yes;

string xml = doc.outerXml(Yes.PrettyOutput);


3. Load xml from utf-8 encoded text file

import pham.xml_new;

auto doc = new XmlDocument!string().loadFromFile("c:\\a-file-name.xml");


4. Save xml from a document to a file name

doc.saveToFile("c:\\a-file-name.xml");

or

import std.typecons : Yes;

doc.saveToFile("c:\\a-file-name.xml", Yes.PrettyOutput);


3. Navigate all sub-nodes of a node

import std.typecons : Yes;

auto nodeList = doc.documentElement.firstChild().getChildNodes(null, Yes.deep);

foreach (node; nodeList)

{

...

}


4. Navigate all child nodes of a node

auto nodeList = doc.documentElement.lastChild().getChildNodes();

foreach (node; nodeList)

{

...

}


5. Navigate sub-elements of a document

import std.typecons : Yes;

auto elementList = doc.getElements(null, Yes.deep);

foreach (element; elementList)

{

...

}


6. Navigate all attributes of an element

auto attributeList = doc.documentElement.getAttributes();

foreach (attribute; attributeList)

{

...

}


7. Use XPath

import pham.xml_xpath;

auto selectedNodes = doc.documentElement.selectNodes("descendant::book[author/last-name='Austen']");

foreach (node; selectedNodes)

{

...

}

or

auto selectedNode = doc.documentElement.selectSingleNode("descendant::book[author/last-name='Austen']");


8. Load using SAX as filter

import pham.xml_new;

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
</bookstore>
XML";
    
    
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


doc.load(xml);

assert(doc.outerXml() == "<bookstore><book><title>Pride And Prejudice</title></book><book><title>The Handmaid's Tale</title></book></bookstore>");



