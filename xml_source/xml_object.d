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

template isDLink(T)
if (is(T == class))
{
    static if (__traits(hasMember, T, "_next") && __traits(hasMember, T, "_prev"))
        enum isDLink = true;
    else
        enum isDLink = false;
}

pragma (inline, true)
package bool dlinkHasPrev(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode) const nothrow @safe
if (isDLink!TLinkNode)
{
    return checkNode !is lastNode._prev;
}

pragma (inline, true)
package bool dlinkHasNext(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode) const nothrow @safe
if (isDLink!TLinkNode)
{
    return checkNode !is lastNode._next;
}

package TLinkNode dlinkInsertAfter(TLinkNode)(TLinkNode refNode, TLinkNode newNode) nothrow @safe
if (isDLink!TLinkNode)
in 
{
    assert(refNode !is null);
    assert(refNode._next !is null);
}
body
{
    newNode._next = refNode._next;
    newNode._prev = refNode;
    refNode._next._prev = newNode;
    refNode._next = newNode;
    return newNode;
}

package TLinkNode dlinkInsertEnd(TLinkNode)(ref TLinkNode lastNode, TLinkNode newNode) nothrow @safe
if (isDLink!TLinkNode)
{
    if (lastNode is null)
    {
        newNode._next = newNode;
        newNode._prev = newNode;
    }
    else
        dlinkInsertAfter(lastNode, newNode);
    lastNode = newNode;
    return newNode;
}

package TLinkNode dlinkRemove(TLinkNode)(ref TLinkNode lastNode, TLinkNode oldNode) nothrow @safe
if (isDLink!TLinkNode)
{
    if (oldNode._next is oldNode)
        lastNode = null;
    else
    {
        oldNode._next._prev = oldNode._prev;
        oldNode._prev._next = oldNode._next;
        if (oldNode is lastNode)
            lastNode = oldNode._prev;
    }
    oldNode._next = null;
    oldNode._prev = null;
    return oldNode;
}

/** Initialize parameter v if it is null in thread safe manner using pass in aInitiate function
    Params:
        v = variable to be initialized to object T if it is null
        aInitiate = a function that returns the newly created object as of T
    Returns:
        parameter v
*/
T singleton(T)(ref T v, T function() aInitiate)
if (is(T == class))
{
    if (v is null)
    {
        synchronized
        {
            if (v is null)
                v = aInitiate();
        }
    }

    return v;
}

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