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

module pham.utl_singleton;

import core.atomic : atomicFence;

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
        atomicFence();
        synchronized
        {
            if (v is null)
                v = aInitiate();
        }
    }

    return v;
}

