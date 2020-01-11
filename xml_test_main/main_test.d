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
import pham.xml_unittest;

__gshared bool outputXmlTraceTiming;

private struct TestItem
{
public:
    string inFileName, outFileName, errFileName;
    string inXml;
    const(char)[] outXml, errXml;
    Duration timeElapsedDuration;
    bool autoSaveOutXml, error, getOutXml, loadFromFile;

    this(string xml)
    {
        this.inXml = xml;
    }

    this(string fileName,
        Flag!"LoadFromFile" loadFromFile,
        Flag!"AutoSaveOutXml" autoSaveOutXml)
    {
        getOutXml = true;
        this.inFileName = fileName;
        this.autoSaveOutXml = autoSaveOutXml;
        this.loadFromFile = loadFromFile;
        outFileName = setExtension(fileName, ".out");

        if (!loadFromFile)
        {
            auto temp = cast(ubyte[]) std.file.read(fileName);

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
                        temp[2], temp[3], formatNumber!size_t(temp.length), formatNumber!size_t(inXml.length));
                else if (temp.length >= 2)
                    outputXmlTraceParserF("chars: %X.%X; lens: %s/%s",
                        temp[0], temp[1], formatNumber!size_t(temp.length), formatNumber!size_t(inXml.length));
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
        if (outXml.length != 0 && outFileName.length != 0)
        {
            // "wb" = open for writing as-is (no extra CR for CRLF chars)
            auto fHandle = File(outFileName, "wb");
            fHandle.write(outXml);
            fHandle.close();
        }

        if (errXml.length != 0 && errFileName.length != 0)
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

    void append(const TestResult value)
    {
        elapsedTime += value.elapsedTime;
        errorCount += value.errorCount;
        totalCount += value.totalCount;
    }

@property:
    uint okCount()
    in
    {
        assert(totalCount >= errorCount);
    }
    do
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
                timingXml = profileXml;
            }
            else debug (xmlTraceParser)
            {
                testXmlSourceFileName = ".\\xml_test\\test\\xmltest.xml";
            }
            else version (unittest)
            {
                outputXmlTraceTiming = false;
            }
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
            if (s.length == 2 && s[1].length != 0)
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

ulong getGCSize(bool begin, bool timing)
{
    version (none)
    {
        import core.sys.windows.windows;

        MEMORYSTATUSEX status;
        status.dwLength = MEMORYSTATUSEX.sizeof;
        GlobalMemoryStatusEx(status);
        return status.ullTotalVirtual - status.ullAvailVirtual;
    }

    if (begin)
    {
        GC.collect();
        if (timing)
            GC.disable();
    }

    auto stats = GC.stats();

    if (!begin)
    {
        if (timing)
            GC.enable();
    }

    return stats.usedSize; // + stats.freeSize;
}

struct TestExecute
{
public:
    alias LoadEvent = Object function(string xml);
    alias SaveEvent = const(char)[] function(Object doc);

private:
    LoadEvent load;
    LoadEvent loadFromFile;
    SaveEvent save;

    bool executeItem(ref TestItem testItem, size_t iteratedCount)
    {
        version (unittest)
        if (isXmlTraceProgress && testItem.inFileName.length != 0)
            outputXmlTraceProgress("executeItem: ", testItem.inFileName);

        auto timeStart = MonoTime.currTime;
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
                if (doc && iteratedCount == 1 && testItem.getOutXml)
                    testItem.outXml = save(doc);
                testItem.error = false;
            }
            catch (Exception e)
            {
                testItem.error = true;                
                if (testItem.inXml.length != 0)
                    testItem.errXml = testItem.inXml ~ "\n\n\n" ~ e.toString();
                else
                    testItem.errXml = e.toString();
                if (testItem.inFileName.length != 0)
                    testItem.errFileName = setExtension(testItem.inFileName, ".err");

                if (testItem.getOutXml)
                    break;
                else
                    throw e;
            }
        }
        while (--iteratedCount > 0);
        testItem.timeElapsedDuration = MonoTime.currTime - timeStart;

        return !testItem.error;
    }

    TestResult executeItems(ref TestItem[] testItems, size_t eachIteratedCount)
    {
        TestResult testResult;

        foreach (ref e; testItems)
        {
            ++testResult.totalCount;
            if (!executeItem(e, eachIteratedCount))
                ++testResult.errorCount;
            testResult.elapsedTime += e.elapsedTime;
        }

        return testResult;
    }

public:
    this(LoadEvent load, LoadEvent loadFromFile, SaveEvent save)
    {
        this.load = load;
        this.loadFromFile = loadFromFile;
        this.save = save;
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

        if (options.timingXml.length != 0)
        {
            version (traceXmlProfile)
            {
                //removeFile("trace.log");
                //writeln("timingXml length: ", formatNumber!size_t(options.timingXml.length));
            }

            testResult.append(timingXml(options.timingXml, options.timingIteratedCount));
        }

        if (options.timingXmlFileName.length != 0)
            testResult.append(timingFile(options.timingXmlFileName, options.timingIteratedCount, No.LoadFromFile, Yes.AutoSaveOutXml));

        if (options.testXmlSourceDirectory.length != 0)
            testResult.append(timingDirectory(options.testXmlSourceDirectory, No.LoadFromFile, Yes.AutoSaveOutXml));

        if (options.testXmlSourceFileName.length != 0)
            testResult.append(timingFile(options.testXmlSourceFileName, 1, No.LoadFromFile, Yes.AutoSaveOutXml));

        version (unittest)
        if (options.expectedOkCount != 0)
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

    TestResult timingDirectory(string directory,
        Flag!"LoadFromFile" loadFromFile,
        Flag!"AutoSaveOutXml" autoSaveOutXml)
    {
        version (unittest)
        if (isXmlTraceProgress && directory.length != 0)
            outputXmlTraceProgress("testDirectory: ", directory);

        TestItem[] testItems;

        foreach (fileName; dirEntries(directory, "*.xml", SpanMode.breadth))
            testItems ~= TestItem(fileName, loadFromFile, autoSaveOutXml);

        auto testResult = executeItems(testItems, 1);

        if (outputXmlTraceTiming)
            writefln("testDirectory elapsed (total %s with error %s) in milli-seconds: %s",
                formatNumber!uint(testResult.totalCount),
                formatNumber!uint(testResult.errorCount),
                formatNumber!long(testResult.elapsedTime));

        foreach (ref e; testItems)
        {
            if (e.outFileName.length != 0)
                e.writeOutXml();
        }

        return testResult;
    }

    TestResult timingFile(string fileName, uint iteratedCount,
        Flag!"LoadFromFile" loadFromFile,
        Flag!"AutoSaveOutXml" autoSaveOutXml)
    {
        auto testItem = TestItem(fileName, loadFromFile, autoSaveOutXml);

        TestResult testResult;
        ++testResult.totalCount;
        if (!executeItem(testItem, iteratedCount))
            ++testResult.errorCount;
        testResult.elapsedTime = testItem.elapsedTime;

        if (outputXmlTraceTiming)
            writefln("timingFile elapsed (iterated %s) in milli-seconds: %s",
                formatNumber!uint(iteratedCount),
                formatNumber!long(testItem.elapsedTime));

        return testResult;
    }

    TestResult timingXml(string xml, uint iteratedCount)
    {
        auto testItem = TestItem(xml);

        TestResult testResult;
        ++testResult.totalCount;
        if (!executeItem(testItem, iteratedCount))
            ++testResult.errorCount;
        testResult.elapsedTime += testItem.elapsedTime;

        if (outputXmlTraceTiming)
            writefln("timingXml elapsed (iterated %s) in milli-seconds: %s",
                formatNumber!uint(iteratedCount),
                formatNumber!long(testItem.elapsedTime));

        return testResult;
    }
}

private enum defaultIteratedCount = 1000;
private enum defaultXmlTestOkCount = 460;
private immutable string defaultXmlTestDirectory = ".\\xml_test";
private immutable string defaultXmlTestFileName = ".\\xml_test\\book.xml";
private immutable string defaultXmlTimingFile = ".\\xml_test\\book.xml";
