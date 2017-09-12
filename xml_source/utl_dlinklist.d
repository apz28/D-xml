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

module pham.utl_dlinklist;

template isDLink(T)
if (is(T == class))
{
    static if (__traits(hasMember, T, "_next") && __traits(hasMember, T, "_prev"))
        enum isDLink = true;
    else
        enum isDLink = false;
}

pragma (inline, true)
bool dlinkHasPrev(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode) const nothrow @safe
if (isDLink!TLinkNode)
{
    return checkNode !is lastNode._prev;
}

pragma (inline, true)
bool dlinkHasNext(TLinkNode)(TLinkNode lastNode, TLinkNode checkNode) const nothrow @safe
if (isDLink!TLinkNode)
{
    return checkNode !is lastNode._next;
}

TLinkNode dlinkInsertAfter(TLinkNode)(TLinkNode refNode, TLinkNode newNode) nothrow @safe
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

TLinkNode dlinkInsertEnd(TLinkNode)(ref TLinkNode lastNode, TLinkNode newNode) nothrow @safe
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

TLinkNode dlinkRemove(TLinkNode)(ref TLinkNode lastNode, TLinkNode oldNode) nothrow @safe
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
