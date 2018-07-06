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

module pham.xml_object;

import pham.xml_msg;
import pham.xml_util;

struct XmlIdentifierList(S = string)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

public:
    const(C)[][const(C)[]] items;

    /** Returns true if name, n, is existed in table; otherwise false
        Params:
            n = is a name to be searched for        
    */
    bool exist(const(C)[] n) const nothrow
    {
        auto e = n in items;
        return e !is null;
    }

    /** Insert name, n, into table
        Params:
            n = is a name to be inserted
        Returns:
            existing its name, n
    */
    const(C)[] put(const(C)[] n) nothrow
    in
    {
        assert(n.length != 0);
    }
    body
    {
        auto e = n in items;
        if (e is null)
        {
            items[n] = n;
            return n;
        }
        else
            return *e;
    }

    alias items this;
}

abstract class XmlObject(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;
}

/** Returns the class-name of aObject.
    If it is null, returns "null"
    Params:
        aObject = the object to get the class-name from
*/
string className(Object aObject) pure nothrow @safe
{
    if (aObject is null)
        return "null";
    else
        return aObject.classinfo.name;
}

/** Returns the short class-name of aObject.
    If it is null, returns "null"
    Params:
        aObject = the object to get the class-name from
*/
string shortClassName(Object aObject) pure nothrow @safe
{
    import std.array : join, split;
    import std.algorithm.iteration : filter;
    import std.string : indexOf;

    if (aObject is null)
        return "null";
    else
    {
        string className = aObject.classinfo.name;
        return split(className, ".").filter!(e => e.indexOf('!') < 0).join(".");
    }
}
