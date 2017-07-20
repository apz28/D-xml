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

module pham.xml_entity_table;

import pham.xml_util;
import pham.xml_object;

class XmlEntityTable(S) : XmlObject!S
{
private:
    __gshared static XmlEntityTable!S _defaultEntityTable;

    static XmlEntityTable!S createDefaultEntityTable()
    {
        return new XmlEntityTable!S();
    }

protected:
    final void initDefault()
    {
        data["&amp;"] = "&";
        data["&apos;"] = "'";
        data["&gt;"] = ">";
        data["&lt;"] = "<";
        data["&quot;"] = "\"";

        data.rehash();
    }

public:
    S[S] data;

    this()
    {
        initDefault();
    }

    static const(XmlEntityTable!S) defaultEntityTable()
    {
        return singleton!(XmlEntityTable!S)(_defaultEntityTable, &createDefaultEntityTable);
    }

    final bool find(S encodedValue, ref S decodedValue) const
    {
        const S* r = encodedValue in data;

        if (r is null)
            return false;
        else
        {
            decodedValue = *r;
            return true;
        }
    }

    final void reset()
    {
        data = null;
        initDefault();
    }

    alias data this;
}

unittest // XmlEntityTable.defaultEntityTable
{
    outputXmlTraceProgress("unittest XmlEntityTable.defaultEntityTable");

    auto table = XmlEntityTable!string.defaultEntityTable();
    assert(table !is null);

    string s;

    assert(table.find("&amp;", s));
    assert(s == "&");

    assert(table.find("&apos;", s));
    assert(s == "'");

    assert(table.find("&gt;", s));
    assert(s == ">");

    assert(table.find("&lt;", s));
    assert(s == "<");

    assert(table.find("&quot;", s));
    assert(s == "\"");

    assert(table.find("", s) == false);
    assert(table.find("&;", s) == false);
    assert(table.find("?", s) == false);
}