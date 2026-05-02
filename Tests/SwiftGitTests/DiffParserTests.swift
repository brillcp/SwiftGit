import Testing
import Foundation
@testable import SwiftGit

@Suite("GitDiffParser Tests")
struct DiffParserTests {
    let parser = GitDiffParser()

    // MARK: - Basic parsing

    @Test func emptyInputProducesNoHunks() async {
        let hunks = await parser.parse("")
        #expect(hunks.isEmpty)
    }

    @Test func headerOnlyProducesNoHunks() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.isEmpty)
    }

    @Test func singleHunkParsedCorrectly() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
        -let x = 1
        +let x = 2
          let y = 3
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        let hunk = hunks[0]
        #expect(hunk.lines.count == 3)
        #expect(hunk.lines[0].type == .removed)
        #expect(hunk.lines[1].type == .added)
        #expect(hunk.lines[2].type == .unchanged)
    }

    @Test func multipleHunksParsedCorrectly() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
        -let x = 1
        +let x = 2
          let y = 3
        @@ -10,3 +10,3 @@
          let a = 1
        -let b = 2
        +let b = 99
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 2)
        #expect(hunks[0].lines[0].type == .removed)
        #expect(hunks[1].lines[1].type == .removed)
        #expect(hunks[1].lines[2].type == .added)
    }

    @Test func hunkHeaderStripped() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@ func myFunction() {
        -let x = 1
        +let x = 2
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        // Context hint after the second @@ should be stripped
        #expect(hunks[0].header == "@@ -1,3 +1,3 @@ ")
    }

    @Test func lineContentsCorrect() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
        -old line
        +new line
         context line
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        let lines = hunks[0].lines
        #expect(lines[0].type == .removed)
        #expect(lines[0].segments.map(\.text).joined() == "old line")
        #expect(lines[1].type == .added)
        #expect(lines[1].segments.map(\.text).joined() == "new line")
        #expect(lines[2].type == .unchanged)
        #expect(lines[2].segments.map(\.text).joined() == "context line")
    }

    @Test func binaryFileSkipped() async {
        let diff = """
        diff --git a/image.png b/image.png
        index abc123..def456 100644
        Binary files a/image.png and b/image.png differ
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.isEmpty)
    }

    @Test func noNewlineAtEndFlagSet() async {
        let diff = """
        diff --git a/foo.txt b/foo.txt
        index abc123..def456 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,2 +1,2 @@
        -old
        +new
        \\ No newline at end of file
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        #expect(hunks[0].hasNoNewlineAtEnd == true)
    }

    @Test func hunkIDsAreSequential() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,2 +1,2 @@
        -a
        +b
        @@ -10,2 +10,2 @@
        -c
        +d
        @@ -20,2 +20,2 @@
        -e
        +f
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 3)
        #expect(hunks[0].id == 0)
        #expect(hunks[1].id == 1)
        #expect(hunks[2].id == 2)
    }

    // MARK: - Word diff (segment highlighting)

    @Test func identicalLinesCollapsedToUnchanged() async {
        // When -/+ lines have identical text (partial-staging artefact), they
        // should be collapsed into a single unchanged context line.
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,2 +1,2 @@
        -same text
        +same text
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        #expect(hunks[0].lines.count == 1)
        #expect(hunks[0].lines[0].type == .unchanged)
    }

    @Test func wordDiffHighlightsChangedToken() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,2 +1,2 @@
        -let x = 1
        +let x = 2
        """
        let hunks = await parser.parse(diff)
        #expect(hunks.count == 1)
        let lines = hunks[0].lines
        #expect(lines.count == 2)

        // The removed line should have "1" highlighted
        let removedHighlighted = lines[0].segments.filter(\.isHighlighted).map(\.text)
        #expect(removedHighlighted == ["1"])

        // The added line should have "2" highlighted
        let addedHighlighted = lines[1].segments.filter(\.isHighlighted).map(\.text)
        #expect(addedHighlighted == ["2"])
    }

    @Test func wordDiffUnchangedTokensNotHighlighted() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,2 +1,2 @@
        -let foo = bar
        +let foo = baz
        """
        let hunks = await parser.parse(diff)
        let lines = hunks[0].lines
        // Only the trailing identifier that changed ("bar" / "baz") should be highlighted.
        // "let ", "foo ", "= " are shared and must not be highlighted.
        let removedHighlighted = lines[0].segments.filter(\.isHighlighted).map(\.text)
        let addedHighlighted   = lines[1].segments.filter(\.isHighlighted).map(\.text)
        #expect(removedHighlighted == ["bar"])
        #expect(addedHighlighted   == ["baz"])
    }

    @Test func soloAddedLineNotHighlighted() async {
        // A solo added line (no preceding removed) should have no highlighted segments
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,1 +1,2 @@
          context
        +new line added
        """
        let hunks = await parser.parse(diff)
        let lines = hunks[0].lines
        let addedLine = lines.first { $0.type == .added }
        #expect(addedLine != nil)
        let highlighted = addedLine?.segments.filter(\.isHighlighted) ?? []
        #expect(highlighted.isEmpty)
    }

    @Test func lineIDsAreSequentialPerHunk() async {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc123..def456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
        -a
        +b
          c
        @@ -10,2 +10,2 @@
        -d
        +e
        """
        let hunks = await parser.parse(diff)
        // Each hunk resets line IDs to 0
        #expect(hunks[0].lines[0].id == 0)
        #expect(hunks[0].lines[1].id == 1)
        #expect(hunks[0].lines[2].id == 2)
        #expect(hunks[1].lines[0].id == 0)
        #expect(hunks[1].lines[1].id == 1)
    }
}
