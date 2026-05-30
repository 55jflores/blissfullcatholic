//
//  CitationParser.swift
//  Blissful Catholic
//
//  Turns lectionary citation strings ("Acts 18:9–18", "1 Cor 12:31—13:13",
//  "Sir 24:1–22", "Lk 1:46–55, 53–55") into structured BibleReference values.
//
//  Tolerates: hyphen / en-dash / em-dash, periods on abbreviations, missing
//  spaces (e.g. "Jn3:16"), verse letter suffixes (5:1a → 5:1), comma-separated
//  multi-part citations, chapter-only references (whole chapter), and chapter
//  spans (12:31–13:13).
//

import Foundation

enum CitationParser {

    /// Parse a citation string into one or more structured references.
    /// Returns an empty array if no valid book/range could be identified.
    static func parse(_ citation: String) -> [BibleReference] {
        // Normalise: unify dashes, drop periods, trim, lowercase for matching.
        let normalized = citation
            .replacingOccurrences(of: "–", with: "-")  // en-dash
            .replacingOccurrences(of: "—", with: "-")  // em-dash
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()

        // Match the book name at the start (longest match wins).
        guard let match = matchBook(in: lower) else { return [] }

        // Whatever follows the matched book name is the chapter/verse spec.
        let specStart = normalized.index(normalized.startIndex, offsetBy: match.matchedLength)
        let spec = String(normalized[specStart...]).trimmingCharacters(in: .whitespaces)

        return parseSpec(spec, book: match.code)
    }

    // MARK: Book-name matching

    /// Try to match a book name at the start of `lower`, preferring longer matches.
    /// The character right after the match must be a space or a digit (so "Mt 5:3"
    /// and "Mt5:3" both work, but "Mtg" doesn't accidentally match "Mt").
    private static func matchBook(in lower: String) -> (code: String, matchedLength: Int)? {
        for (name, code) in bookNamesSorted {
            guard lower.hasPrefix(name) else { continue }
            let endIdx = lower.index(lower.startIndex, offsetBy: name.count)
            if endIdx == lower.endIndex {
                return (code, name.count)
            }
            let next = lower[endIdx]
            if next == " " || next.isNumber {
                return (code, name.count)
            }
        }
        return nil
    }

    // MARK: Spec parsing

    /// Parse "chapter[:verse][-...][, more]" into one or more references.
    /// State note: in "23:1, 3-5" the trailing "3-5" inherits chapter 23.
    private static func parseSpec(_ spec: String, book: String) -> [BibleReference] {
        guard !spec.isEmpty else { return [] }
        let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        var refs: [BibleReference] = []
        var carriedChapter: Int? = nil
        for part in parts {
            if let ref = parseRangePart(String(part), book: book, carriedChapter: carriedChapter) {
                refs.append(ref)
                carriedChapter = ref.endChapter
            }
        }
        return refs
    }

    /// Parse a single dash-separated range like "5:3-12", "12:31-13:13", "3-5", or "23".
    private static func parseRangePart(_ part: String, book: String, carriedChapter: Int?) -> BibleReference? {
        let sides = part.split(separator: "-", maxSplits: 1).map(String.init)
        let lhs = sides[0]
        let rhs = sides.count > 1 ? sides[1] : lhs

        let (startChapOpt, startVerseOpt) = parseChapterVerse(lhs, defaultChapter: carriedChapter)
        let (endChapOpt, endVerseOpt) = parseChapterVerse(rhs, defaultChapter: startChapOpt ?? carriedChapter)

        // Whole-chapter reference (no verse on either side, e.g. "Ps 23")
        if startVerseOpt == nil && endVerseOpt == nil {
            guard let sc = startChapOpt else { return nil }
            let ec = endChapOpt ?? sc
            return BibleReference(
                book: book,
                startChapter: sc, startVerse: 1,
                endChapter: ec, endVerse: Int.max
            )
        }

        guard let sc = startChapOpt else { return nil }
        let ec = endChapOpt ?? sc
        let sv = startVerseOpt ?? 1
        let ev = endVerseOpt ?? sv

        return BibleReference(
            book: book,
            startChapter: sc, startVerse: sv,
            endChapter: ec, endVerse: ev
        )
    }

    /// Parse "5:3" / "5" / "3" — for the last form, the chapter comes from
    /// `defaultChapter` (e.g. the second part of "23:1, 3-5" inherits 23).
    /// Verse letter suffixes ("3a", "12b") are stripped.
    private static func parseChapterVerse(_ s: String, defaultChapter: Int?) -> (chapter: Int?, verse: Int?) {
        let cleaned = s.replacingOccurrences(of: " ", with: "")
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", maxSplits: 1).map(String.init)
            let chap = Int(parts[0].filter { $0.isNumber })
            let verseStr = parts.count > 1 ? parts[1] : ""
            let verse = Int(verseStr.prefix { $0.isNumber })
            return (chap, verse)
        } else {
            let n = Int(cleaned.prefix { $0.isNumber })
            if defaultChapter != nil {
                return (defaultChapter, n)
            }
            return (n, nil)
        }
    }

    // MARK: Book name dictionary (Catholic canon)
    //
    // Lowercased, dot-free. Lectionary uses many short abbreviations (Mt, Jn,
    // 1 Pt, Sir, …); we accept full names + the common short forms. Longer
    // matches win via the sort below, so "1 corinthians" beats "1 cor", and
    // "john" beats "jn", regardless of input.

    private static let bookNames: [(String, String)] = [
        // Old Testament (46 books in the Catholic canon)
        ("genesis", "GEN"), ("gen", "GEN"), ("gn", "GEN"),
        ("exodus", "EXO"), ("exod", "EXO"), ("ex", "EXO"),
        ("leviticus", "LEV"), ("lev", "LEV"), ("lv", "LEV"),
        ("numbers", "NUM"), ("num", "NUM"), ("nm", "NUM"),
        ("deuteronomy", "DEU"), ("deut", "DEU"), ("dt", "DEU"),
        ("joshua", "JOS"), ("josh", "JOS"), ("jos", "JOS"),
        ("judges", "JDG"), ("judg", "JDG"), ("jgs", "JDG"), ("jdg", "JDG"),
        ("ruth", "RUT"), ("ru", "RUT"),
        ("1 samuel", "1SA"), ("1samuel", "1SA"),
        ("1 sam", "1SA"), ("1sam", "1SA"), ("1 sm", "1SA"), ("1sm", "1SA"),
        ("2 samuel", "2SA"), ("2samuel", "2SA"),
        ("2 sam", "2SA"), ("2sam", "2SA"), ("2 sm", "2SA"), ("2sm", "2SA"),
        ("1 kings", "1KI"), ("1kings", "1KI"), ("1 kgs", "1KI"), ("1kgs", "1KI"),
        ("2 kings", "2KI"), ("2kings", "2KI"), ("2 kgs", "2KI"), ("2kgs", "2KI"),
        ("1 chronicles", "1CH"), ("1chronicles", "1CH"), ("1 chr", "1CH"), ("1chr", "1CH"),
        ("2 chronicles", "2CH"), ("2chronicles", "2CH"), ("2 chr", "2CH"), ("2chr", "2CH"),
        ("ezra", "EZR"), ("ezr", "EZR"),
        ("nehemiah", "NEH"), ("neh", "NEH"),
        ("tobit", "TOB"), ("tob", "TOB"), ("tb", "TOB"),
        ("judith", "JDT"), ("jdt", "JDT"),
        ("esther", "EST"), ("esth", "EST"), ("est", "EST"),
        ("1 maccabees", "1MA"), ("1maccabees", "1MA"),
        ("1 mac", "1MA"), ("1mac", "1MA"), ("1 mc", "1MA"), ("1mc", "1MA"),
        ("2 maccabees", "2MA"), ("2maccabees", "2MA"),
        ("2 mac", "2MA"), ("2mac", "2MA"), ("2 mc", "2MA"), ("2mc", "2MA"),
        ("job", "JOB"), ("jb", "JOB"),
        ("psalms", "PSA"), ("psalm", "PSA"), ("ps", "PSA"), ("pss", "PSA"),
        ("proverbs", "PRO"), ("prov", "PRO"), ("prv", "PRO"),
        ("ecclesiastes", "ECC"), ("eccl", "ECC"), ("ecc", "ECC"),
        ("song of songs", "SNG"), ("song", "SNG"), ("sng", "SNG"), ("sg", "SNG"),
        ("wisdom", "WIS"), ("wis", "WIS"),
        ("sirach", "SIR"), ("sir", "SIR"),
        ("isaiah", "ISA"), ("isa", "ISA"), ("is", "ISA"),
        ("jeremiah", "JER"), ("jer", "JER"),
        ("lamentations", "LAM"), ("lam", "LAM"),
        ("baruch", "BAR"), ("bar", "BAR"),
        ("ezekiel", "EZK"), ("ezek", "EZK"), ("ezk", "EZK"), ("ez", "EZK"),
        ("daniel", "DAN"), ("dan", "DAN"), ("dn", "DAN"),
        ("hosea", "HOS"), ("hos", "HOS"),
        ("joel", "JOL"), ("jl", "JOL"),
        ("amos", "AMO"), ("am", "AMO"),
        ("obadiah", "OBA"), ("obad", "OBA"), ("ob", "OBA"),
        ("jonah", "JON"), ("jon", "JON"),
        ("micah", "MIC"), ("mic", "MIC"), ("mi", "MIC"),
        ("nahum", "NAM"), ("nah", "NAM"), ("na", "NAM"),
        ("habakkuk", "HAB"), ("hab", "HAB"), ("hb", "HAB"),
        ("zephaniah", "ZEP"), ("zeph", "ZEP"), ("zep", "ZEP"),
        ("haggai", "HAG"), ("hag", "HAG"), ("hg", "HAG"),
        ("zechariah", "ZEC"), ("zech", "ZEC"), ("zec", "ZEC"),
        ("malachi", "MAL"), ("mal", "MAL"),

        // New Testament (27 books)
        ("matthew", "MAT"), ("matt", "MAT"), ("mt", "MAT"),
        ("mark", "MRK"), ("mrk", "MRK"), ("mk", "MRK"),
        ("luke", "LUK"), ("lk", "LUK"),
        ("john", "JHN"), ("jn", "JHN"),
        ("acts of the apostles", "ACT"), ("acts", "ACT"),
        ("romans", "ROM"), ("rom", "ROM"),
        ("1 corinthians", "1CO"), ("1corinthians", "1CO"), ("1 cor", "1CO"), ("1cor", "1CO"),
        ("2 corinthians", "2CO"), ("2corinthians", "2CO"), ("2 cor", "2CO"), ("2cor", "2CO"),
        ("galatians", "GAL"), ("gal", "GAL"),
        ("ephesians", "EPH"), ("eph", "EPH"),
        ("philippians", "PHP"), ("phil", "PHP"), ("php", "PHP"),
        ("colossians", "COL"), ("col", "COL"),
        ("1 thessalonians", "1TH"), ("1thessalonians", "1TH"),
        ("1 thess", "1TH"), ("1thess", "1TH"), ("1 thes", "1TH"), ("1thes", "1TH"),
        ("2 thessalonians", "2TH"), ("2thessalonians", "2TH"),
        ("2 thess", "2TH"), ("2thess", "2TH"), ("2 thes", "2TH"), ("2thes", "2TH"),
        ("1 timothy", "1TI"), ("1timothy", "1TI"), ("1 tim", "1TI"), ("1tim", "1TI"),
        ("2 timothy", "2TI"), ("2timothy", "2TI"), ("2 tim", "2TI"), ("2tim", "2TI"),
        ("titus", "TIT"), ("tit", "TIT"),
        ("philemon", "PHM"), ("phlm", "PHM"), ("phm", "PHM"),
        ("hebrews", "HEB"), ("heb", "HEB"),
        ("james", "JAS"), ("jas", "JAS"),
        ("1 peter", "1PE"), ("1peter", "1PE"),
        ("1 pet", "1PE"), ("1pet", "1PE"), ("1 pt", "1PE"), ("1pt", "1PE"),
        ("2 peter", "2PE"), ("2peter", "2PE"),
        ("2 pet", "2PE"), ("2pet", "2PE"), ("2 pt", "2PE"), ("2pt", "2PE"),
        ("1 john", "1JN"), ("1john", "1JN"), ("1 jn", "1JN"), ("1jn", "1JN"),
        ("2 john", "2JN"), ("2john", "2JN"), ("2 jn", "2JN"), ("2jn", "2JN"),
        ("3 john", "3JN"), ("3john", "3JN"), ("3 jn", "3JN"), ("3jn", "3JN"),
        ("jude", "JUD"),
        ("revelation", "REV"), ("rev", "REV"), ("apocalypse", "REV"),
    ]

    /// Longer keys first, so "1 corinthians" beats "1 cor" beats "1c"
    /// regardless of input casing/length.
    private static let bookNamesSorted: [(String, String)] = {
        bookNames.sorted { $0.0.count > $1.0.count }
    }()
}
