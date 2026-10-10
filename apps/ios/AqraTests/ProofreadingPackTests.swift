import CryptoKit
import SwiftUI
import Testing
@testable import Aqra

/// The pack the owner's team proofreads before release: all 604 pages as the app draws them, with tajweed colors
/// and without, one PDF per juz', and a sign-off sheet to record each juz' as checked.
///
/// Renders only when `AQRA_PROOFREADING_OUT` names an output folder (pass `TEST_RUNNER_AQRA_PROOFREADING_OUT` to
/// xcodebuild, with `-only-testing:AqraTests/ProofreadingPackTests`); skipped otherwise, like the snapshots.
/// `AQRA_PROOFREADING_COMMIT` adds the commit the pack was made from to the sheet.
@MainActor
struct ProofreadingPackTests {
    /// The page as on an iPhone 17, in points: the size the app is used at most. The PDF is vector, so it zooms.
    private static let pageSize = CGSize(width: 402, height: 874)
    /// A4, for the sign-off sheet.
    private static let sheetSize = CGSize(width: 595, height: 842)

    struct Juz {
        var number: Int
        var pages: ClosedRange<Int>
        var file: String { String(format: "juz-%02d.pdf", number) }
    }

    @Test func renderPack() throws {
        guard let path = ProcessInfo.processInfo.environment["AQRA_PROOFREADING_OUT"] else { return }
        let folder = URL(fileURLWithPath: path)
        AqraFont.registerBundledFonts()
        let store = try MushafStore()

        // Each page in exactly one juz' file: from the page its juz' starts on to the page before the next one.
        let starts = (1...30).map { try! #require(store.juzStartPages[$0]) }
        let juzs = (1...30).map { number in
            Juz(number: number, pages: starts[number - 1]...(number < 30 ? starts[number] - 1 : MushafStore.pageCount))
        }
        #expect(juzs.map(\.pages.count).reduce(0, +) == MushafStore.pageCount)

        for (mode, tajweed) in [("tajweed", true), ("plain", false)] {
            let modeFolder = folder.appendingPathComponent(mode)
            try FileManager.default.createDirectory(at: modeFolder, withIntermediateDirectories: true)
            for juz in juzs {
                try renderPDF(to: modeFolder.appendingPathComponent(juz.file), size: Self.pageSize, pages: Array(juz.pages)) { number in
                    AnyView(MushafPageView(page: store.page(number), store: store)
                        .environment(\.mushafTajweed, tajweed)
                        .environment(\.mushafTopics, false))
                }
            }
        }

        let fontsManifest = try #require(MushafStore.resourceURL("qcf4.sha256"))
        let fontsHash = SHA256.hash(data: try Data(contentsOf: fontsManifest)).map { String(format: "%02x", $0) }.joined()
        let commit = ProcessInfo.processInfo.environment["AQRA_PROOFREADING_COMMIT"] ?? "—"
        let made = Date.now.formatted(.iso8601.year().month().day())
        let rowsPerSheet = 15
        let sheets = stride(from: 0, to: juzs.count, by: rowsPerSheet).map { Array(juzs[$0..<min($0 + rowsPerSheet, juzs.count)]) }
        try renderPDF(to: folder.appendingPathComponent("sign-off-sheet.pdf"), size: Self.sheetSize, pages: Array(sheets.indices)) { index in
            AnyView(SignOffSheet(rows: sheets[index], sheet: index + 1, of: sheets.count, commit: commit, fontsHash: fontsHash, made: made))
        }

        // The same sheet as a spreadsheet, with a byte-order mark so Excel reads the Arabic.
        var csv = "\u{FEFF}Juz' / الجزء,Pages / الصفحات,File / الملف,Tajweed checked / بالتجويد,Plain checked / دون تجويد,Reviewer / المراجِع,Date / التاريخ,Differences (page:line) / الفروق (الصفحة:السطر)\n"
        for juz in juzs {
            csv += "\(juz.number),\(juz.pages.lowerBound)–\(juz.pages.upperBound),\(juz.file),,,,,\n"
        }
        try csv.write(to: folder.appendingPathComponent("sign-off-sheet.csv"), atomically: true, encoding: .utf8)
    }

    /// Draws each page into one vector PDF, a PDF page per view.
    private func renderPDF(to url: URL, size: CGSize, pages: [Int], view: (Int) -> AnyView) throws {
        var box = CGRect(origin: .zero, size: size)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil), "can't write \(url.path)")
        for page in pages {
            let renderer = ImageRenderer(content: view(page).frame(width: size.width, height: size.height))
            renderer.proposedSize = ProposedViewSize(size)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
    }
}

/// One A4 page of the sign-off sheet, in Arabic and English.
private struct SignOffSheet: View {
    var rows: [ProofreadingPackTests.Juz]
    var sheet: Int
    var of: Int
    var commit: String
    var fontsHash: String
    var made: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Mushaf page fonts: proofreading sign-off")
                    .font(.system(size: 15, weight: .heavy))
                Spacer()
                Text(verbatim: "مراجعة خطوط صفحات المصحف: الإقرار")
                    .font(.system(size: 15, weight: .heavy))
            }
            if sheet == 1 {
                Text(verbatim: "Compare every page of tajweed/juz-NN.pdf and plain/juz-NN.pdf with the King Fahd Complex's printed Madinah Mushaf (Hafs, 15 lines, 1441H). Tick a juz' only when all its pages match in both files, and write any difference as page:line.")
                    .font(.system(size: 9))
                Text(verbatim: "قابِلوا كل صفحة في ملفّي \u{2066}tajweed/juz-NN.pdf\u{2069} و\u{2066}plain/juz-NN.pdf\u{2069} بمصحف المدينة المطبوع في مجمع الملك فهد (حفص، ١٥ سطرًا، ١٤٤١هـ). لا يُعلَّم الجزء إلا إذا طابقت صفحاته كلها في الملفين، وتُكتب الفروق بصيغة الصفحة:السطر.")
                    .font(.system(size: 9))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                Text(verbatim: "Made \(made) · commit \(commit) · fonts manifest (qcf4.sha256) SHA-256 \(fontsHash)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    header("Juz'\nالجزء", width: 40); header("Pages\nالصفحات", width: 62)
                    header("Tajweed\nبالتجويد", width: 46); header("Plain\nدون تجويد", width: 46)
                    header("Reviewer\nالمراجِع", width: 92); header("Date\nالتاريخ", width: 62)
                    header("Differences (page:line)\nالفروق (الصفحة:السطر)", width: 191)
                }
                ForEach(rows, id: \.number) { juz in
                    GridRow {
                        cell("\(juz.number)", width: 40); cell("\(juz.pages.lowerBound)–\(juz.pages.upperBound)", width: 62)
                        box(); box(); cell("", width: 92); cell("", width: 62); cell("", width: 191)
                    }
                }
            }
            .font(.system(size: 9))
            Spacer(minLength: 0)
            Text(verbatim: "Sheet \(sheet) of \(of) · Aqra")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func header(_ text: String, width: CGFloat) -> some View {
        Text(verbatim: text)
            .font(.system(size: 8, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(width: width, height: 32)
            .border(.black.opacity(0.6), width: 0.5)
            .background(Color(white: 0.93))
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(verbatim: text)
            .frame(width: width, height: 36)
            .border(.black.opacity(0.6), width: 0.5)
    }

    private func box() -> some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(.black, lineWidth: 0.8)
            .frame(width: 12, height: 12)
            .frame(width: 46, height: 36)
            .border(.black.opacity(0.6), width: 0.5)
    }
}
