import Foundation
import CoreGraphics

struct DetectedEvent: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var endDate: Date? = nil
    var isAllDay: Bool = false
    var isDefaultTime: Bool = false
    var location: String? = nil
    var notes: String? = nil
}

struct OCRLine {
    let text: String
    let box: CGRect
}

enum EventDetectionService {
    static func detect(lines rawLines: [OCRLine], referenceDate: Date) -> [DetectedEvent] {
        let lines = rawLines
            .map { OCRLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return [] }

        var mentions: [Mention] = []
        for (index, line) in lines.enumerated() {
            mentions.append(contentsOf: findMentions(in: line, index: index, ref: referenceDate))
        }
        guard !mentions.isEmpty else { return [] }

        let cal0 = Calendar.current
        let certainDays = Set(mentions.filter { $0.alternative == nil }.map { cal0.startOfDay(for: $0.start) })
        mentions = mentions.map { mention in
            guard let alt = mention.alternative,
                  certainDays.contains(cal0.startOfDay(for: alt)),
                  !certainDays.contains(cal0.startOfDay(for: mention.start)) else { return mention }
            return Mention(lineIndex: mention.lineIndex, start: alt, end: mention.end, coversLine: mention.coversLine)
        }

        let headingIndexes = Set(mentions.filter(\.coversLine).map(\.lineIndex))

        var blockIndexes = Set<Int>()
        var drafts: [(mention: Mention, block: [Int], timeTexts: [String])] = []

        for mention in mentions {
            let line = lines[mention.lineIndex]
            var timeTexts = [line.text]
            timeTexts.append(contentsOf: rowNeighbors(of: mention.lineIndex, in: lines).map { lines[$0].text })

            var block: [Int] = []
            if mention.coversLine {
                block = blockLines(below: mention.lineIndex, in: lines, stopAt: headingIndexes)
                blockIndexes.formUnion(block)
                timeTexts.append(contentsOf: block.prefix(2).map { lines[$0].text })
            }
            drafts.append((mention, block, timeTexts))
        }

        let dateLineIndexes = Set(mentions.map(\.lineIndex))
        let docTitle = documentTitle(lines: lines, excluding: dateLineIndexes.union(blockIndexes))
        let isMulti = Set(mentions.map { Calendar.current.startOfDay(for: $0.start) }).count > 1
        let allText = lines.map(\.text).joined(separator: "\n")
        let location = extractLocation(from: lines.map(\.text))

        var events: [DetectedEvent] = []

        for draft in drafts {
            let mention = draft.mention
            let line = lines[mention.lineIndex]
            let cal = Calendar.current

            var start = mention.start
            var end = mention.end
            var allDay = mention.end != nil
            var isDefaultTime = false
            if mention.end == nil {
                let time = firstTimes(in: draft.timeTexts)
                isDefaultTime = time == nil
                var comps = cal.dateComponents([.year, .month, .day], from: start)
                comps.hour = time?.start.h ?? 8
                comps.minute = time?.start.m ?? 0
                if let withTime = cal.date(from: comps) {
                    start = withTime
                    if let endTime = time?.end {
                        var endComps = comps
                        endComps.hour = endTime.h
                        endComps.minute = endTime.m
                        if let endDate = cal.date(from: endComps), endDate > start { end = endDate }
                    }
                } else {
                    allDay = true
                }
            }

            let blockTexts = draft.block.map { cleanBullet(lines[$0].text) }.filter { !$0.isEmpty }
            let notes: String?
            if !blockTexts.isEmpty {
                notes = blockTexts.joined(separator: "\n")
            } else if isMulti {
                notes = line.text
            } else {
                notes = String(allText.prefix(600))
            }

            let title = docTitle
                ?? blockTexts.first
                ?? "Event from Photo"

            events.append(DetectedEvent(
                title: title,
                date: start,
                endDate: end,
                isAllDay: allDay,
                isDefaultTime: isDefaultTime,
                location: location,
                notes: notes
            ))
        }

        return dedupe(events)
    }

    private static let monthMap: [String: Int] = [
        "januari": 1, "february": 2, "februari": 2, "maret": 3, "april": 4, "mei": 5,
        "juni": 6, "juli": 7, "agustus": 8, "september": 9, "oktober": 10,
        "november": 11, "desember": 12,
        "january": 1, "march": 3, "may": 5, "june": 6, "july": 7, "august": 8,
        "october": 10, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7,
        "aug": 8, "agu": 8, "agt": 8, "ags": 8, "sep": 9, "sept": 9,
        "oct": 10, "okt": 10, "nov": 11, "dec": 12, "des": 12
    ]

    private static let weekdayMap: [String: Int] = [
        "minggu": 1, "senin": 2, "selasa": 3, "rabu": 4, "kamis": 5, "jumat": 6, "jum'at": 6, "sabtu": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7
    ]

    private static func alternation(_ keys: Dictionary<String, Int>.Keys) -> String {
        keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    private enum Kind {
        case rangeDayFirst, rangeMonthFirst, crossDayFirst, crossMonthFirst
        case singleDayFirst, singleMonthFirst
        case iso, dayMonthYearNumeric
    }

    private static let patterns: [(Kind, NSRegularExpression)] = {
        let m = alternation(monthMap.keys)
        let w = alternation(weekdayMap.keys)
        let sep = #"(?:-|–|—|to|s/d|s\.d\.|sampai|hingga|until)"#
        let ord = #"(?:st|nd|rd|th)?"#
        let year = #"(?:,?\s+(?<y>(?:19|20)\d{2})(?!\d))?"#
        let wd = #"(?:(?<wd>"# + w + #")\.?,?\s+)?"#

        let defs: [(Kind, String)] = [
            (.rangeDayFirst, #"\b"# + wd + #"(?<d1>\d{1,2})"# + ord + #"\s*"# + sep + #"\s*(?<d2>\d{1,2})"# + ord + #"(?!\d)\s+(?:of\s+)?(?<m1>"# + m + #")\b\.?"# + year),
            (.rangeMonthFirst, #"\b(?<m1>"# + m + #")\b\.?\s+(?<d1>\d{1,2})"# + ord + #"\s*"# + sep + #"\s*(?<d2>\d{1,2})"# + ord + #"(?!\d)"# + year),
            (.crossDayFirst, #"\b(?<d1>\d{1,2})"# + ord + #"\s+(?<m1>"# + m + #")\b\.?\s*"# + sep + #"\s*(?<d2>\d{1,2})"# + ord + #"\s+(?<m2>"# + m + #")\b\.?"# + year),
            (.crossMonthFirst, #"\b(?<m1>"# + m + #")\b\.?\s+(?<d1>\d{1,2})"# + ord + #"\s*"# + sep + #"\s*(?<m2>"# + m + #")\b\.?\s+(?<d2>\d{1,2})"# + ord + #"(?!\d)"# + year),
            (.singleDayFirst, #"\b"# + wd + #"(?<d1>\d{1,2})"# + ord + #"\s+(?:of\s+)?(?<m1>"# + m + #")\b\.?"# + year),
            (.singleMonthFirst, #"\b"# + wd + #"(?<m1>"# + m + #")\b\.?\s+(?<d1>\d{1,2})"# + ord + #"(?!\d)(?!\s*[.:]\d)"# + year),
            (.iso, #"(?<![\d.\/-])(?<y>(?:19|20)\d{2})[-/.](?<m1>\d{1,2})[-/.](?<d1>\d{1,2})(?!\d)"#),
            (.dayMonthYearNumeric, #"(?<![\d.\/-])(?<d1>\d{1,2})[-/.](?<m1>\d{1,2})[-/.](?<y>(?:19|20)\d{2})(?!\d)"#)
        ]

        return defs.compactMap { kind, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                print("⚠️ EventDetection: pola regex gagal dibuat untuk \(kind)")
                return nil
            }
            return (kind, regex)
        }
    }()

    private struct Mention {
        let lineIndex: Int
        let start: Date
        let end: Date?
        let coversLine: Bool
        var alternative: Date? = nil
    }

    private static func findMentions(in line: OCRLine, index: Int, ref: Date) -> [Mention] {
        let text = line.text
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var taken: [NSRange] = []
        var result: [Mention] = []

        for (kind, regex) in patterns {
            for match in regex.matches(in: text, options: [], range: full) {
                if taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                guard let dates = buildDates(kind: kind, match: match, regex: regex, text: ns, ref: ref) else { continue }

                let coverage = Double(match.range.length) / Double(max(text.count, 1))
                taken.append(match.range)
                result.append(Mention(lineIndex: index, start: dates.start, end: dates.end, coversLine: coverage >= 0.8, alternative: dates.alt))
            }
        }
        return result
    }

    private static func buildDates(kind: Kind, match: NSTextCheckingResult, regex: NSRegularExpression, text: NSString, ref: Date) -> (start: Date, end: Date?, alt: Date?)? {
        func group(_ name: String) -> String? {
            guard regex.pattern.contains("(?<\(name)>") else { return nil }
            let r = match.range(withName: name)
            return r.location == NSNotFound ? nil : text.substring(with: r)
        }
        func number(_ name: String) -> Int? { group(name).flatMap { Int($0) } }
        func month(_ name: String) -> Int? {
            guard let token = group(name) else { return nil }
            if token.lowercased() == "may" && token != "May" && token != "MAY" { return nil }
            return monthMap[token.lowercased()]
        }

        let calendar = Calendar(identifier: .gregorian)
        let weekday = group("wd").flatMap { weekdayMap[$0.lowercased()] }
        let year = number("y")

        switch kind {
        case .rangeDayFirst, .rangeMonthFirst:
            guard let d1 = number("d1"), let d2 = number("d2"), let m = month("m1"), d2 > d1,
                  let start = makeDate(day: d1, month: m, year: year, weekday: weekday, ref: ref) else { return nil }
            let startYear = calendar.component(.year, from: start)
            guard let end = makeDate(day: d2, month: m, year: startYear, weekday: nil, ref: ref) else { return nil }
            return (start, end, nil)

        case .crossDayFirst, .crossMonthFirst:
            guard let d1 = number("d1"), let d2 = number("d2"), let m1 = month("m1"), let m2 = month("m2"),
                  let start = makeDate(day: d1, month: m1, year: year, weekday: weekday, ref: ref) else { return nil }
            var endYear = calendar.component(.year, from: start)
            guard var end = makeDate(day: d2, month: m2, year: endYear, weekday: nil, ref: ref) else { return nil }
            if end < start {
                endYear += 1
                guard let next = makeDate(day: d2, month: m2, year: endYear, weekday: nil, ref: ref) else { return nil }
                end = next
            }
            return (start, end, nil)

        case .singleDayFirst, .singleMonthFirst:
            guard let d = number("d1"), let m = month("m1"),
                  let start = makeDate(day: d, month: m, year: year, weekday: weekday, ref: ref) else { return nil }
            return (start, nil, nil)

        case .iso:
            guard let y = year, let m = number("m1"), let d = number("d1"),
                  let start = makeDate(day: d, month: m, year: y, weekday: nil, ref: ref) else { return nil }
            return (start, nil, nil)

        case .dayMonthYearNumeric:
            guard let y = year, let a = number("d1"), let b = number("m1") else { return nil }
            let primary = b <= 12 ? makeDate(day: a, month: b, year: y, weekday: nil, ref: ref) : nil
            let swapped = a <= 12 ? makeDate(day: b, month: a, year: y, weekday: nil, ref: ref) : nil
            if let primary { return (primary, nil, (swapped != primary) ? swapped : nil) }
            if let swapped { return (swapped, nil, nil) }
            return nil
        }
    }

    private static func makeDate(day: Int, month: Int, year: Int?, weekday: Int?, ref: Date) -> Date? {
        let cal = Calendar(identifier: .gregorian)

        func date(_ y: Int) -> Date? {
            var c = DateComponents()
            c.year = y
            c.month = month
            c.day = day
            guard let d = cal.date(from: c) else { return nil }
            let back = cal.dateComponents([.year, .month, .day], from: d)
            return (back.year == y && back.month == month && back.day == day) ? d : nil
        }

        if let year { return date(year) }

        let refYear = cal.component(.year, from: ref)

        if let weekday {
            let matches = [refYear - 1, refYear, refYear + 1].compactMap { y -> Date? in
                guard let d = date(y), cal.component(.weekday, from: d) == weekday else { return nil }
                return d
            }
            if let best = matches.min(by: { abs($0.timeIntervalSince(ref)) < abs($1.timeIntervalSince(ref)) }) {
                return best
            }
        }

        guard var d = date(refYear) else { return nil }
        if d < ref.addingTimeInterval(-180 * 86_400), let next = date(refYear + 1) { d = next }
        return d
    }

    private struct TimeOfDay { let h: Int; let m: Int }

    private static let time24Regex = try? NSRegularExpression(
        pattern: #"(?<![\d.:])(?<h>[01]?\d|2[0-3])(?<sep>[.:])(?<mi>[0-5]\d)(?!\d|[.:]\d)"#
    )
    private static let timeAMPMRegex = try? NSRegularExpression(
        pattern: #"(?<![\d.:])(?<h>1[0-2]|0?[1-9])(?:[.:](?<mi>[0-5]\d))?\s*(?<ap>[ap])\.?m\b"#,
        options: [.caseInsensitive]
    )

    private static func times(in text: String) -> [TimeOfDay] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [(loc: Int, time: TimeOfDay)] = []

        for match in time24Regex?.matches(in: text, options: [], range: full) ?? [] {
            guard let h = Int(ns.substring(with: match.range(withName: "h"))),
                  let mi = Int(ns.substring(with: match.range(withName: "mi"))) else { continue }
            let sep = ns.substring(with: match.range(withName: "sep"))
            if sep == "." && ![0, 15, 30, 45].contains(mi) { continue }
            found.append((match.range.location, TimeOfDay(h: h, m: mi)))
        }

        for match in timeAMPMRegex?.matches(in: text, options: [], range: full) ?? [] {
            guard var h = Int(ns.substring(with: match.range(withName: "h"))) else { continue }
            let miRange = match.range(withName: "mi")
            let mi = miRange.location == NSNotFound ? 0 : (Int(ns.substring(with: miRange)) ?? 0)
            let isPM = ns.substring(with: match.range(withName: "ap")).lowercased() == "p"
            if h == 12 { h = isPM ? 12 : 0 } else if isPM { h += 12 }
            found.append((match.range.location, TimeOfDay(h: h, m: mi)))
        }

        return found.sorted { $0.loc < $1.loc }.map(\.time)
    }

    private static func firstTimes(in texts: [String]) -> (start: TimeOfDay, end: TimeOfDay?)? {
        for text in texts {
            let found = times(in: text)
            guard let first = found.first else { continue }
            var end: TimeOfDay?
            if found.count >= 2 {
                let second = found[1]
                if second.h * 60 + second.m > first.h * 60 + first.m { end = second }
            }
            return (first, end)
        }
        return nil
    }

    private static func rowNeighbors(of index: Int, in lines: [OCRLine]) -> [Int] {
        let box = lines[index].box
        return lines.indices.filter { j in
            guard j != index else { return false }
            let other = lines[j].box
            return abs(other.midY - box.midY) < max(box.height, other.height) * 0.7
        }
    }

    private static func blockLines(below index: Int, in lines: [OCRLine], stopAt headings: Set<Int>) -> [Int] {
        let heading = lines[index].box
        let candidates = lines.indices
            .filter { j in
                guard j != index else { return false }
                let box = lines[j].box
                return box.maxY <= heading.minY + 0.01
                    && abs(box.minX - heading.minX) < 0.07
                    && heading.minY - box.maxY < 0.35
            }
            .sorted { lines[$0].box.maxY > lines[$1].box.maxY }

        var result: [Int] = []
        var previousMinY = heading.minY

        for j in candidates {
            let box = lines[j].box
            let gap = previousMinY - box.maxY
            if gap > max(0.03, box.height * 1.8) { break }
            if headings.contains(j) { break }
            if letterCount(lines[j].text) >= 2 { result.append(j) }
            previousMinY = box.minY
        }
        return result
    }

    private static func letterCount(_ text: String) -> Int {
        text.filter { $0.isLetter }.count
    }

    private static func cleanBullet(_ text: String) -> String {
        text.replacingOccurrences(of: #"^[\s\-–—•*·>]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func documentTitle(lines: [OCRLine], excluding excluded: Set<Int>) -> String? {
        let candidates = lines.indices.filter { !excluded.contains($0) && letterCount(lines[$0].text) >= 3 }
        guard let biggest = candidates.max(by: { lines[$0].box.height < lines[$1].box.height }) else { return nil }

        let maxHeight = lines[biggest].box.height
        let group = candidates.filter { j in
            lines[j].box.height >= maxHeight * 0.8
                && abs(lines[j].box.midY - lines[biggest].box.midY) <= maxHeight * 2.2
        }
        .sorted { lines[$0].box.midY > lines[$1].box.midY }

        let title = group.map { lines[$0].text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(title.prefix(60))
    }

    private static func extractLocation(from texts: [String]) -> String? {
        let regex = try? NSRegularExpression(pattern: #"^\s*(?:location|venue|place|lokasi|tempat)\s*[:：]\s*(.+)$"#, options: [.caseInsensitive])
        for text in texts {
            let ns = text as NSString
            guard let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges > 1 else { continue }
            let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func dedupe(_ events: [DetectedEvent]) -> [DetectedEvent] {
        var result: [DetectedEvent] = []
        for event in events.sorted(by: { $0.date < $1.date }) {
            if let index = result.firstIndex(where: { existing in
                let cal = Calendar.current
                guard cal.isDate(existing.date, inSameDayAs: event.date) else { return false }
                if existing.isAllDay || event.isAllDay || existing.isDefaultTime || event.isDefaultTime { return true }
                return cal.component(.hour, from: existing.date) == cal.component(.hour, from: event.date)
                    && cal.component(.minute, from: existing.date) == cal.component(.minute, from: event.date)
            }) {
                if (result[index].isAllDay || result[index].isDefaultTime) && !event.isAllDay && !event.isDefaultTime {
                    result[index].date = event.date
                    result[index].isAllDay = false
                    result[index].isDefaultTime = false
                }
                if result[index].endDate == nil { result[index].endDate = event.endDate }
                if (event.notes?.count ?? 0) > (result[index].notes?.count ?? 0) { result[index].notes = event.notes }
            } else {
                result.append(event)
            }
        }
        return Array(result.prefix(40))
    }
}
