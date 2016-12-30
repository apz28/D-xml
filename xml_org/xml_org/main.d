module main;

import std.xml;
import main_test;

Object loadXml(string xml)
{
    return new Document(xml);
}

string saveXml(Object doc)
{
    return (cast(Document) doc).toString();
}

int main(string[] argv)
{
    TestOptions o = TestOptions(argv);

    TestExecute t = TestExecute(&loadXml, null, &saveXml);
    t.execute(o);

    return 0;
}
