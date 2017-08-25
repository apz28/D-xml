module main;

import kxml.xml;
import main_test;

Object loadXml(string xml)
{
    auto doc = new XmlDocument();
    doc.parse(xml);
    return doc;
}

string saveXml(Object doc)
{
    return (cast(XmlDocument) doc).toString();
}

int main(string[] argv)
{
    TestOptions o = TestOptions(argv);

    TestExecute t = TestExecute(&loadXml, null, &saveXml);
    t.execute(o);

    return 0;
}
