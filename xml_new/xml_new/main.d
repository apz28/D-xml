/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2016 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module main;

import std.typecons : No, Yes;

import pham.xml_dom;
import pham.xml_xpath;
import main_test;

Object loadXml(string xml)
{
    auto doc = new XmlDocument!string();
    return doc.load(xml);
}

Object loadXmlFromFile(string fileName)
{
    auto doc = new XmlDocument!string();
    return doc.loadFromFile(fileName);
}

const(char)[] saveXml(Object doc)
{
    return (cast(XmlDocument!string)doc).outerXml(Yes.prettyOutput);
}

int main(string[] argv)
{
    TestOptions o = TestOptions(argv);

    TestExecute t = TestExecute(&loadXml, &loadXmlFromFile, &saveXml);
    t.execute(o);

    return 0;
}
