/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2016 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module main_test;

import core.memory;
import core.time;
import std.array : split;
import std.conv : to;
import std.path : setExtension;
import std.typecons : Flag, No, Yes;
import std.file;
import std.stdio;

import pham.xml_util;

__gshared bool outputXmlTraceTiming;

private struct TestItem
{
public:
    string inFileName, outFileName, errFileName;
    string inXml, outXml, errXml;
    Duration timeElapsedDuration;
    bool autoSaveOutXml, error, getOutXml, loadFromFile;

    this(string aXml)
    {
        inXml = aXml;
    }

    this(string aFileName,
        Flag!"LoadFromFile" aLoadFromFile,
        Flag!"AutoSaveOutXml" aAutoSaveOutXml)
    {
        getOutXml = true;
        inFileName = aFileName;
        autoSaveOutXml = aAutoSaveOutXml;
        loadFromFile = aLoadFromFile;
        outFileName = setExtension(aFileName, ".out");

        if (!loadFromFile)
        {
            ubyte[] temp = cast(ubyte[]) std.file.read(aFileName);

            switch (getEncodedMarker(temp))
            {
                case XmlEncodedMarker.utf8:
                    inXml = cast(string)(cast(char[]) temp[3 .. $]);
                    break;
                case XmlEncodedMarker.utf16be:
                    inXml = to!string(cast(wstring)(cast(wchar[]) temp[2 .. $]));
                    break;
                case XmlEncodedMarker.utf16le:
                    inXml = to!string(cast(wstring)(cast(wchar[]) temp[2 .. $]));
                    break;
                case XmlEncodedMarker.utf32be:
                    inXml = to!string(cast(dstring)(cast(dchar[]) temp[4 .. $]));
                    break;
                case XmlEncodedMarker.utf32le:
                    inXml = to!string(cast(dstring)(cast(dchar[]) temp[4 .. $]));
                    break;
                default:
                    inXml = cast(string) temp;
            }

            version (unittest)
            {
                if (temp.length >= 4)
                    outputXmlTraceParserF("chars: %X.%X.%X.%X; lens: %s/%s", temp[0], temp[1],
                        temp[2], temp[3], 
                        formatNumber!size_t(temp.length),
                        formatNumber!size_t(inXml.length));
                else if (temp.length >= 2)
                    outputXmlTraceParserF("chars: %X.%X; lens: %s/%s",
                        temp[0], temp[1], 
                        formatNumber!size_t(temp.length),
                        formatNumber!size_t(inXml.length));
            }
        }
    }

    ~this()
    {
        if (autoSaveOutXml)
            writeOutXml();
    }

    void writeOutXml()
    {
        if (outXml.length > 0 && outFileName.length > 0)
        {
            // "wb" = open for writing as-is (no extra CR for CRLF chars)
            auto fHandle = File(outFileName, "wb");
            fHandle.write(outXml);
            fHandle.close();
        }

        if (errXml.length > 0 && errFileName.length > 0)
        {
            // "wb" = open for writing as-is (no extra CR for CRLF chars)
            auto fHandle = File(errFileName, "wb");
            fHandle.write(errXml);
            fHandle.close();
        }
    }

@property:
    long elapsedTime()
    {
        return timeElapsedDuration.total!"msecs";
    }
}

private struct TestResult
{
public:
    long elapsedTime;
    uint errorCount;
    uint totalCount;

    void clear()
    {
        elapsedTime = 0;
        errorCount = 0;
        totalCount = 0;
    }

    void append(const TestResult aValue)
    {
        elapsedTime += aValue.elapsedTime;
        errorCount += aValue.errorCount;
        totalCount += aValue.totalCount;
    }

@property:
    uint okCount()
    in
    {
        assert(totalCount >= errorCount);
    }
    body
    {
        return totalCount - errorCount;
    }
}

struct TestOptions
{
    string testXmlSourceDirectory;
    string testXmlSourceFileName;
    string timingXml;
    string timingXmlFileName;
    size_t timingIteratedCount;
    uint expectedOkCount;

    this(string[] argv)
    {
        outputXmlTraceTiming = true;
        expectedOkCount = 0;

        debug
        {
            timingIteratedCount = 1;
            debug (xmlTraceProfile)
            {
                outputXmlTraceTiming = false;
                timingXml = defaultXmlProfile;
            }
            else debug (xmlTraceParser)
                testXmlSourceFileName = ".\\xml_test\\test\\xmltest.xml";
            else
            {
                testXmlSourceDirectory = defaultXmlTestDirectory;
                testXmlSourceFileName = defaultXmlTestFileName;
                expectedOkCount = defaultXmlTestOkCount;
            }
        }
        else
        {
            timingIteratedCount = defaultIteratedCount;
            timingXmlFileName = defaultXmlTimingFile;
        }

        foreach (e; argv)
        {
            if (e == "help" || e == "?")
            {
                testXmlSourceDirectory = "";
                testXmlSourceFileName = "";
                timingXml = "";
                timingXmlFileName = "";

                writeln("testSourceDirectory=\"...?\"");
                writeln("testSourceFileName=\"...?\"");
                writeln("timingFileName=\"...?\"");
                writeln("expectedOkCount=...n");

                break;
            }

            string[] s = e.split('=');
            if (s.length == 2 && s[1].length > 0)
            {
                if (s[0] == "timingFileName")
                    timingXmlFileName = s[1];
                else if (s[0] == "testSourceDirectory")
                {
                    testXmlSourceDirectory = s[1];
                    expectedOkCount = 0;
                }
                else if (s[0] == "testSourceFileName")
                {
                    testXmlSourceFileName = s[1];
                    expectedOkCount = 0;
                }
                else if (s[0] == "expectedOkCount")
                    expectedOkCount = to!uint(s[1]);
            }
        }
    }
}

ulong getGCSize(bool aBegin, bool aTiming)
{
    version (none)
    {
        import core.sys.windows.windows;

        MEMORYSTATUSEX status;
        status.dwLength = MEMORYSTATUSEX.sizeof;
        GlobalMemoryStatusEx(status);
        return (status.ullTotalVirtual - status.ullAvailVirtual);
    }

    if (aBegin)
    {
        GC.collect();
        if (aTiming)
            GC.disable();
    }

    auto stats = GC.stats();

    if (!aBegin)
    {
        if (aTiming)
            GC.enable();
    }

    return stats.usedSize; // + stats.freeSize;
}

struct TestExecute
{
public:
    alias LoadEvent = Object function(string xml);
    alias SaveEvent = string function(Object doc);

private:
    LoadEvent load;
    LoadEvent loadFromFile;
    SaveEvent save;

    bool executeItem(ref TestItem testItem, size_t aIteratedCount)
    {
        version (unittest)
        if (isXmlTraceProgress && testItem.inFileName.length > 0)
            outputXmlTraceProgress("executeItem: ", testItem.inFileName);

        MonoTime timeStart = MonoTime.currTime;
        do
        {
            try
            {
                Object doc;
                if (testItem.loadFromFile)
                {
                    if (loadFromFile)
                        doc = loadFromFile(testItem.inFileName);
                }
                else
                    doc = load(testItem.inXml);
                if (doc && aIteratedCount == 1 && testItem.getOutXml)
                    testItem.outXml = save(doc);
                testItem.error = false;
            }
            catch (Exception e)
            {
                testItem.error = true;                
                if (testItem.inXml.length > 0)
                    testItem.errXml = testItem.inXml ~ "\n\n\n" ~ e.toString();
                else
                    testItem.errXml = e.toString();
                if (testItem.inFileName.length > 0)
                    testItem.errFileName = setExtension(testItem.inFileName, ".err");

                if (testItem.getOutXml)
                    break;
                else
                    throw e;
            }
        }
        while (--aIteratedCount > 0);
        testItem.timeElapsedDuration = MonoTime.currTime - timeStart;

        return !testItem.error;
    }

    TestResult executeItems(ref TestItem[] testItems, size_t aEachIteratedCount)
    {
        TestResult testResult;

        foreach (ref e; testItems)
        {
            ++testResult.totalCount;
            if (!executeItem(e, aEachIteratedCount))
                ++testResult.errorCount;
            testResult.elapsedTime += e.elapsedTime;
        }

        return testResult;
    }

public:
    this(LoadEvent aLoad, LoadEvent aLoadFromFile, SaveEvent aSave)
    {
        load = aLoad;
        loadFromFile = aLoadFromFile;
        save = aSave;
    }

    TestResult execute(TestOptions options)
    {
        TestResult testResult;

        bool memTiming = outputXmlTraceTiming && options.testXmlSourceDirectory.length == 0;
        ulong memBeginSize = getGCSize(true, memTiming);
        scope (exit)
        {
            ulong memEndSize = getGCSize(false, memTiming);
            if (outputXmlTraceTiming)
                writefln("memory usage: begin: %s, end: %s, diff: %s", 
                    formatNumber!ulong(memBeginSize), 
                    formatNumber!ulong(memEndSize), 
                    formatNumber!ulong(memEndSize - memBeginSize));
        }

        if (options.timingXml.length > 0)
        {
            version (traceXmlProfile)
            {
                //removeFile("trace.log");
                //writeln("timingXml length: ", formatNumber!size_t(options.timingXml.length));
            }

            testResult.append(timingXml(options.timingXml, options.timingIteratedCount));
        }

        if (options.timingXmlFileName.length > 0)
            testResult.append(timingFile(options.timingXmlFileName, options.timingIteratedCount, No.LoadFromFile, Yes.AutoSaveOutXml));

        if (options.testXmlSourceDirectory.length > 0)
            testResult.append(timingDirectory(options.testXmlSourceDirectory, No.LoadFromFile, Yes.AutoSaveOutXml));

        if (options.testXmlSourceFileName.length > 0)
            testResult.append(timingFile(options.testXmlSourceFileName, 1, No.LoadFromFile, Yes.AutoSaveOutXml));

        version (unittest)
        if (options.expectedOkCount > 0)
        {
            if (options.expectedOkCount != testResult.okCount)
                writefln("execute: error: %s, ok: %s, total: %s, elapsedTime: %s, expectedOkCount: %s", 
                    formatNumber!uint(testResult.errorCount), 
                    formatNumber!uint(testResult.okCount), 
                    formatNumber!uint(testResult.totalCount), 
                    formatNumber!long(testResult.elapsedTime),
                    formatNumber!uint(options.expectedOkCount));

            assert(testResult.okCount == options.expectedOkCount);
        }

        return testResult;
    }

    TestResult timingDirectory(string aDirectory,
        Flag!"LoadFromFile" aLoadFromFile,
        Flag!"AutoSaveOutXml" aAutoSaveOutXml)
    {
        version (unittest)
        if (isXmlTraceProgress && aDirectory.length > 0)
            outputXmlTraceProgress("testDirectory: ", aDirectory);

        TestItem[] testItems;

        foreach (fileName; dirEntries(aDirectory, "*.xml", SpanMode.breadth))
            testItems ~= TestItem(fileName, aLoadFromFile, aAutoSaveOutXml);

        TestResult testResult = executeItems(testItems, 1);

        if (outputXmlTraceTiming)
            writefln("testDirectory elapsed (total %s with error %s) in milli-seconds: %s",
                formatNumber!uint(testResult.totalCount),
                formatNumber!uint(testResult.errorCount),
                formatNumber!long(testResult.elapsedTime));

        foreach (ref e; testItems)
        {
            if (e.outFileName.length > 0)
                e.writeOutXml();
        }

        return testResult;
    }

    TestResult timingFile(string aFileName, uint aIteratedCount,
        Flag!"LoadFromFile" aLoadFromFile,
        Flag!"AutoSaveOutXml" aAutoSaveOutXml)
    {
        TestItem testItem = TestItem(aFileName, aLoadFromFile, aAutoSaveOutXml);

        TestResult testResult;
        ++testResult.totalCount;
        if (!executeItem(testItem, aIteratedCount))
            ++testResult.errorCount;
        testResult.elapsedTime = testItem.elapsedTime;

        if (outputXmlTraceTiming)
            writefln("timingFile elapsed (iterated %s) in milli-seconds: %s",
                formatNumber!uint(aIteratedCount),
                formatNumber!long(testItem.elapsedTime));

        return testResult;
    }

    TestResult timingXml(string aXml, uint aIteratedCount)
    {
        TestItem testItem = TestItem(aXml);

        TestResult testResult;
        ++testResult.totalCount;
        if (!executeItem(testItem, aIteratedCount))
            ++testResult.errorCount;
        testResult.elapsedTime += testItem.elapsedTime;

        if (outputXmlTraceTiming)
            writefln("timingXml elapsed (iterated %s) in milli-seconds: %s",
                formatNumber!uint(aIteratedCount),
                formatNumber!long(testItem.elapsedTime));

        return testResult;
    }
}

private enum defaultIteratedCount = 1000;
private enum defaultXmlTestOkCount = 460;
private immutable string defaultXmlTestDirectory = ".\\xml_test";
private immutable string defaultXmlTestFileName = ".\\xml_test\\book.xml";
private immutable string defaultXmlTimingFile = ".\\xml_test\\book.xml";

// 4604 characters
private immutable string defaultXmlProfile = q"XML
<?xml version="1.0"?>
<catalog>
    <book id="bk101">
        <author>Gambardella, Matthew</author>
        <title>XML Developer's Guide</title>
        <genre>Computer</genre>
        <price>44.95</price>
        <publish_date>2000-10-01</publish_date>
        <description>An in-depth look at creating applications with XML.</description>
    </book>
    <book id="bk102">
        <author>Ralls, Kim</author>
        <title>Midnight Rain</title>
        <genre>Fantasy</genre>
        <price>5.95</price>
        <publish_date>2000-12-16</publish_date>
        <description>A former architect battles corporate zombies, 
        an evil sorceress, and her own childhood to become queen 
        of the world.</description>
    </book>
    <book id="bk103">
        <author>Corets, Eva</author>
        <title>Maeve Ascendant</title>
        <genre>Fantasy</genre>
        <price>5.95</price>
        <publish_date>2000-11-17</publish_date>
        <description>After the collapse of a nanotechnology 
        society in England, the young survivors lay the 
        foundation for a new society.</description>
    </book>
    <book id="bk104">
        <author>Corets, Eva</author>
        <title>Oberon's Legacy</title>
        <genre>Fantasy</genre>
        <price>5.95</price>
        <publish_date>2001-03-10</publish_date>
        <description>In post-apocalypse England, the mysterious 
        agent known only as Oberon helps to create a new life 
        for the inhabitants of London. Sequel to Maeve Ascendant.</description>
    </book>
    <book id="bk105">
        <author>Corets, Eva</author>
        <title>The Sundered Grail</title>
        <genre>Fantasy</genre>
        <price>5.95</price>
        <publish_date>2001-09-10</publish_date>
        <description>The two daughters of Maeve, half-sisters, 
        battle one another for control of England. Sequel to Oberon's Legacy.</description>
    </book>
    <book id="bk106">
        <author>Randall, Cynthia</author>
        <title>Lover Birds</title>
        <genre>Romance</genre>
        <price>4.95</price>
        <publish_date>2000-09-02</publish_date>
        <description>When Carla meets Paul at an ornithology 
        conference, tempers fly as feathers get ruffled.</description>
    </book>
    <book id="bk107">
        <author>Thurman, Paula</author>
        <title>Splish Splash</title>
        <genre>Romance</genre>
        <price>4.95</price>
        <publish_date>2000-11-02</publish_date>
        <description>A deep sea diver finds true love twenty 
        thousand leagues beneath the sea.</description>
    </book>
    <book id="bk108">
        <author>Knorr, Stefan</author>
        <title>Creepy Crawlies</title>
        <genre>Horror</genre>
        <price>4.95</price>
        <publish_date>2000-12-06</publish_date>
        <description>An anthology of horror stories about roaches,
        centipedes, scorpions  and other insects.</description>
    </book>
    <book id="bk109">
        <author>Kress, Peter</author>
        <title>Paradox Lost</title>
        <genre>Science Fiction</genre>
        <price>6.95</price>
        <publish_date>2000-11-02</publish_date>
        <description>After an inadvertant trip through a Heisenberg
        Uncertainty Device, James Salway discovers the problems 
        of being quantum.</description>
    </book>
    <book id="bk110">
        <author>O'Brien, Tim</author>
        <title>Microsoft .NET: The Programming Bible</title>
        <genre>Computer</genre>
        <price>36.95</price>
        <publish_date>2000-12-09</publish_date>
        <description>Microsoft's .NET initiative is explored in 
        detail in this deep programmer's reference.</description>
    </book>
    <book id="bk111">
        <author>O'Brien, Tim</author>
        <title>MSXML3: A Comprehensive Guide</title>
        <genre>Computer</genre>
        <price>36.95</price>
        <publish_date>2000-12-01</publish_date>
        <description>The Microsoft MSXML3 parser is covered in 
        detail, with attention to XML DOM interfaces, XSLT processing, 
        SAX and more.</description>
    </book>
    <book id="bk112">
        <author>Galos, Mike</author>
        <title>Visual Studio 7: A Comprehensive Guide</title>
        <genre>Computer</genre>
        <price>49.95</price>
        <publish_date>2001-04-16</publish_date>
        <description>Microsoft Visual Studio 7 is explored in depth,
        looking at how Visual Basic, Visual C++, C#, and ASP+ are 
        integrated into a comprehensive development environment.</description>
    </book>
</catalog>
XML";
