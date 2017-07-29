module pham.xml_unittest;

static immutable string xpathXml = q"XML
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

static immutable string parserXml = 
q"XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <withAttributeOnly1 emptyAtt1='' emptyAtt2=""/>
  <withAttributeOnly2 att1='single quote' att2="double quote"/>
  <attributeWithNP xmlns:myns="something"/>
  <withAttributeAndChild att1="&lt;&gt;&amp;&apos;&quot;" att2='with double quote ""'>
    <emptyChild1/>
    <emptyChild2></emptyChild2>
  </withAttributeAndChild>
  <nodeWithText>abcd</nodeWithText>
  <nodeWithReservedText>abcd&lt;&gt;&amp;&apos;&quot;abcd</nodeWithReservedText>
  <nodeWithMultiLineText>
    line1
    line2
  </nodeWithMultiLineText>
  <myNS:nodeWithNP/>
  <!-- This is a -- comment -->
  <![CDATA[ dataSection! ]]>
</root>
XML";

static immutable string parserSaxXml =
q"XML
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
