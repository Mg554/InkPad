import UIKit

/// Writes a deck as an editable PowerPoint file (.pptx, which Keynote and
/// Google Slides open too): real text boxes in the theme's colors, the
/// slide icons and page pictures, and speaker notes.
@MainActor
enum PPTXExporter {
    static func export(_ deck: SlideDeck, images: [String: UIImage]) throws -> URL {
        var zip = ZipWriter()
        let count = deck.slides.count
        let palette = deck.theme.palette

        zip.add("[Content_Types].xml", text: Part.contentTypes(slideCount: count))
        zip.add("_rels/.rels", text: Part.rootRelationships)
        zip.add("docProps/core.xml", text: Part.core(title: deck.title, date: deck.modifiedAt))
        zip.add("docProps/app.xml", text: Part.app(slideCount: count))
        zip.add("ppt/presentation.xml", text: Part.presentation(slideCount: count))
        zip.add("ppt/_rels/presentation.xml.rels", text: Part.presentationRelationships(slideCount: count))
        zip.add("ppt/presProps.xml", text: Part.presProps)
        zip.add("ppt/viewProps.xml", text: Part.viewProps)
        zip.add("ppt/tableStyles.xml", text: Part.tableStyles)
        zip.add("ppt/theme/theme1.xml", text: Part.theme(palette))
        zip.add("ppt/theme/theme2.xml", text: Part.theme(palette))
        zip.add("ppt/slideMasters/slideMaster1.xml", text: Part.slideMaster)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", text: Part.relationships([
            Part.relationship("rId1", type: "slideLayout", target: "../slideLayouts/slideLayout1.xml"),
            Part.relationship("rId2", type: "theme", target: "../theme/theme1.xml"),
        ]))
        zip.add("ppt/slideLayouts/slideLayout1.xml", text: Part.slideLayout)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: Part.relationships([
            Part.relationship("rId1", type: "slideMaster", target: "../slideMasters/slideMaster1.xml"),
        ]))
        zip.add("ppt/notesMasters/notesMaster1.xml", text: Part.notesMaster)
        zip.add("ppt/notesMasters/_rels/notesMaster1.xml.rels", text: Part.relationships([
            Part.relationship("rId1", type: "theme", target: "../theme/theme2.xml"),
        ]))

        for (index, slide) in deck.slides.enumerated() {
            let number = index + 1
            var builder = SlideBuilder(palette: palette, images: images)
            builder.add(slide, number: number, total: count)
            var relationships = [
                Part.relationship("rId1", type: "slideLayout", target: "../slideLayouts/slideLayout1.xml"),
                Part.relationship("rId2", type: "notesSlide", target: "../notesSlides/notesSlide\(number).xml"),
            ]
            for picture in builder.media {
                let file = "slide\(number)-\(picture.id).\(picture.ext)"
                zip.add("ppt/media/\(file)", picture.data)
                relationships.append(Part.relationship(picture.id, type: "image", target: "../media/\(file)"))
            }
            zip.add("ppt/slides/slide\(number).xml", text: Part.slide(shapes: builder.xml, background: palette.background))
            zip.add("ppt/slides/_rels/slide\(number).xml.rels", text: Part.relationships(relationships))
            zip.add("ppt/notesSlides/notesSlide\(number).xml", text: Part.notes(slide.speakerNotes))
            zip.add("ppt/notesSlides/_rels/notesSlide\(number).xml.rels", text: Part.relationships([
                Part.relationship("rId1", type: "notesMaster", target: "../notesMasters/notesMaster1.xml"),
                Part.relationship("rId2", type: "slide", target: "../slides/slide\(number).xml"),
            ]))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(deck.title, fallback: "Slides"))
            .appendingPathExtension("pptx")
        try zip.data().write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Slides

/// Lays out one slide as PowerPoint shapes, following `SlideCanvas`. Frames
/// are in its 1280 × 720 design points.
@MainActor
private struct SlideBuilder {
    struct Picture {
        let id: String
        let ext: String
        let data: Data
    }

    let palette: SlidePalette
    let images: [String: UIImage]
    private(set) var xml = ""
    private(set) var media: [Picture] = []
    private var nextShapeID = 2

    init(palette: SlidePalette, images: [String: UIImage]) {
        self.palette = palette
        self.images = images
    }

    mutating func add(_ slide: Slide, number: Int, total: Int) {
        // The soft lights in two corners, as on screen.
        glow(CGRect(x: 520, y: -760, width: 1520, height: 1520), color: palette.glow, alpha: 40)
        glow(CGRect(x: -640, y: 80, width: 1280, height: 1280), color: palette.accent, alpha: 14)

        let bullets = slide.visibleBullets
        switch slide.layout {
        case .title:
            symbol(slide.symbol, color: palette.accent, in: CGRect(x: 90, y: 150, width: 80, height: 80))
            text(CGRect(x: 90, y: 250, width: 1100, height: 220), anchor: "b", paragraphs: [
                Paragraphs.line(slide.title, size: 64, color: palette.title, bold: true),
            ])
            if !slide.subtitle.isEmpty {
                text(CGRect(x: 90, y: 490, width: 1100, height: 90), paragraphs: [
                    Paragraphs.line(slide.subtitle, size: 28, color: palette.text),
                ])
            }
            rectangle(CGRect(x: 90, y: 600, width: 120, height: 8), color: palette.accent, rounded: true)
        case .agenda, .bullets, .summary:
            header(slide)
            let size: Double = bullets.joined().count > 260 ? 22 : 28
            let style: Paragraphs.Marker = slide.layout == .agenda ? .number : .dot
            text(CGRect(x: 90, y: 175, width: 1100, height: 470), paragraphs: bullets.map { bullet in
                Paragraphs.bullet(bullet, size: size, color: palette.text, marker: palette.accent, style: style)
            })
        case .quote:
            text(CGRect(x: 140, y: 150, width: 1000, height: 360), anchor: "ctr", paragraphs: [
                Paragraphs.line("“" + slide.title + "”", size: 40, color: palette.title, italic: true, align: "ctr", font: "Georgia"),
            ])
            if !slide.subtitle.isEmpty {
                text(CGRect(x: 140, y: 530, width: 1000, height: 60), paragraphs: [
                    Paragraphs.line("— " + slide.subtitle, size: 24, color: palette.text, align: "ctr"),
                ])
            }
        case .image:
            text(CGRect(x: 90, y: 60, width: 620, height: 120), anchor: "b", paragraphs: [
                Paragraphs.line(slide.title, size: 40, color: palette.title, bold: true),
            ])
            text(CGRect(x: 90, y: 200, width: 620, height: 420), paragraphs: bullets.prefix(4).map { bullet in
                Paragraphs.bullet(bullet, size: 24, color: palette.text, marker: palette.accent, style: .dot)
            })
            if let file = slide.imageFile, let image = images[file], let jpeg = image.jpegData(compressionQuality: 0.9) {
                picture(jpeg, ext: "jpeg", size: image.size, in: CGRect(x: 760, y: 80, width: 430, height: 560))
            }
        }
        text(CGRect(x: 1040, y: 668, width: 180, height: 30), paragraphs: [
            Paragraphs.line("\(number) / \(total)", size: 14, color: palette.text, align: "r"),
        ])
    }

    /// An icon on an accent tile, then the title beside it.
    private mutating func header(_ slide: Slide) {
        rectangle(CGRect(x: 90, y: 60, width: 76, height: 76), color: palette.accent, rounded: true)
        symbol(slide.symbol, color: palette.onAccent, in: CGRect(x: 106, y: 76, width: 44, height: 44))
        text(CGRect(x: 190, y: 55, width: 1000, height: 86), anchor: "ctr", paragraphs: [
            Paragraphs.line(slide.title, size: 44, color: palette.title, bold: true),
        ])
    }

    private mutating func shapeID() -> Int {
        defer { nextShapeID += 1 }
        return nextShapeID
    }

    private mutating func text(_ frame: CGRect, anchor: String = "t", paragraphs: [String]) {
        guard !paragraphs.isEmpty else { return }
        let id = shapeID()
        xml += Part.joined([
            #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="Text \#(id)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>"#,
            #"<p:spPr>\#(Part.transform(frame))<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>"#,
            #"<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\#(anchor)"><a:normAutofit/></a:bodyPr><a:lstStyle/>"#,
            paragraphs.joined(),
            "</p:txBody></p:sp>",
        ])
    }

    private mutating func rectangle(_ frame: CGRect, color: SlideColor, rounded: Bool) {
        let id = shapeID()
        xml += #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="Shape \#(id)"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"#
            + #"<p:spPr>\#(Part.transform(frame))<a:prstGeom prst="\#(rounded ? "roundRect" : "rect")"><a:avLst/></a:prstGeom>"#
            + #"<a:solidFill><a:srgbClr val="\#(color.hex)"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"#
    }

    /// A circle of color fading out from its middle.
    private mutating func glow(_ frame: CGRect, color: SlideColor, alpha: Int) {
        let id = shapeID()
        xml += Part.joined([
            #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="Glow \#(id)"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"#,
            #"<p:spPr>\#(Part.transform(frame))<a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom>"#,
            #"<a:gradFill rotWithShape="1"><a:gsLst>"#,
            #"<a:gs pos="0"><a:srgbClr val="\#(color.hex)"><a:alpha val="\#(alpha * 1000)"/></a:srgbClr></a:gs>"#,
            #"<a:gs pos="100000"><a:srgbClr val="\#(color.hex)"><a:alpha val="0"/></a:srgbClr></a:gs>"#,
            #"</a:gsLst><a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path></a:gradFill>"#,
            #"<a:ln><a:noFill/></a:ln></p:spPr></p:sp>"#,
        ])
    }

    private mutating func symbol(_ name: String, color: SlideColor, in box: CGRect) {
        guard let image = Self.symbolImage(name, color: color), let png = image.pngData() else { return }
        picture(png, ext: "png", size: image.size, in: box)
    }

    /// A picture fitted inside `box`, keeping its shape.
    private mutating func picture(_ data: Data, ext: String, size: CGSize, in box: CGRect) {
        guard size.width > 0, size.height > 0 else { return }
        let relationship = "rIdMedia\(media.count + 1)"
        media.append(Picture(id: relationship, ext: ext, data: data))
        let scale = min(box.width / size.width, box.height / size.height)
        let fitted = CGRect(
            x: box.midX - size.width * scale / 2,
            y: box.midY - size.height * scale / 2,
            width: size.width * scale,
            height: size.height * scale
        )
        let id = shapeID()
        xml += #"<p:pic><p:nvPicPr><p:cNvPr id="\#(id)" name="Picture \#(id)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"#
            + #"<p:blipFill><a:blip r:embed="\#(relationship)"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"#
            + #"<p:spPr>\#(Part.transform(fitted))<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>"#
    }

    /// An SF Symbol drawn in one color, large enough to stay sharp.
    private static func symbolImage(_ name: String, color: SlideColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 160, weight: .semibold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage(systemName: "sparkles", withConfiguration: configuration)
        else { return nil }
        let tinted = symbol.withTintColor(
            UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
            renderingMode: .alwaysOriginal
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = tinted.size
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            tinted.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Paragraphs of DrawingML text. Arabic paragraphs run right to left.
private enum Paragraphs {
    enum Marker {
        case dot, number
    }

    static func line(
        _ text: String,
        size: Double,
        color: SlideColor,
        bold: Bool = false,
        italic: Bool = false,
        align: String = "l",
        font: String = "Helvetica Neue"
    ) -> String {
        let rtl = SlideSymbols.isArabic(text)
        let alignment = rtl && align == "l" ? "r" : align
        return #"<a:p><a:pPr algn="\#(alignment)" rtl="\#(rtl ? 1 : 0)"/>"#
            + run(text, size: size, color: color, bold: bold, italic: italic, font: font, rtl: rtl)
            + "</a:p>"
    }

    static func bullet(_ text: String, size: Double, color: SlideColor, marker: SlideColor, style: Marker) -> String {
        let rtl = SlideSymbols.isArabic(text)
        let symbol = style == .number
            ? #"<a:buFont typeface="+mj-lt"/><a:buAutoNum type="arabicPeriod"/>"#
            : #"<a:buFont typeface="Arial"/><a:buChar char="•"/>"#
        return Part.joined([
            #"<a:p><a:pPr marL="457200" indent="-457200" algn="\#(rtl ? "r" : "l")" rtl="\#(rtl ? 1 : 0)">"#,
            #"<a:spcBef><a:spcPts val="1400"/></a:spcBef><a:buClr><a:srgbClr val="\#(marker.hex)"/></a:buClr>"#,
            symbol,
            "</a:pPr>",
            run(text, size: size, color: color, bold: false, italic: false, font: "Helvetica Neue", rtl: rtl),
            "</a:p>",
        ])
    }

    static func run(_ text: String, size: Double, color: SlideColor, bold: Bool, italic: Bool, font: String, rtl: Bool) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return #"<a:r><a:rPr lang="\#(rtl ? "ar-SA" : "en-US")" sz="\#(Int(size * 75))" b="\#(bold ? 1 : 0)" i="\#(italic ? 1 : 0)" dirty="0">"#
            + #"<a:solidFill><a:srgbClr val="\#(color.hex)"/></a:solidFill><a:latin typeface="\#(font)"/><a:cs typeface="Geeza Pro"/></a:rPr>"#
            + "<a:t>\(Part.escaped(flat))</a:t></a:r>"
    }
}

// MARK: - Package parts

/// The fixed parts of the package, and helpers for the XML.
private enum Part {
    static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
    static let namespaces = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#
    static let emptyGroup = #"<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>"#
    static let colorMap = #"<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>"#

    /// English Metric Units in one design point (12192000 EMU across 1280 points).
    static let emuPerPoint: CGFloat = 9525

    /// Pieces of XML put together. (Long `+` chains are slow to compile.)
    static func joined(_ pieces: [String]) -> String {
        pieces.joined()
    }

    static func transform(_ frame: CGRect) -> String {
        func emu(_ value: CGFloat) -> Int { Int((value * emuPerPoint).rounded()) }
        return #"<a:xfrm><a:off x="\#(emu(frame.minX))" y="\#(emu(frame.minY))"/><a:ext cx="\#(max(emu(frame.width), 1))" cy="\#(max(emu(frame.height), 1))"/></a:xfrm>"#
    }

    /// Text made safe inside XML, without characters XML cannot hold.
    static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                let value = scalar.value
                let allowed = value >= 0x20 || value == 0x09 || value == 0x0A || value == 0x0D
                if allowed && value != 0xFFFE && value != 0xFFFF {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    static func relationship(_ id: String, type: String, target: String) -> String {
        #"<Relationship Id="\#(id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/\#(type)" Target="\#(target)"/>"#
    }

    static func relationships(_ entries: [String]) -> String {
        joined([
            header,
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
            entries.joined(),
            "</Relationships>",
        ])
    }

    static func contentTypes(slideCount: Int) -> String {
        let main = "application/vnd.openxmlformats-officedocument.presentationml."
        let theme = "application/vnd.openxmlformats-officedocument.theme+xml"
        var overrides: [(String, String)] = [
            ("/ppt/presentation.xml", main + "presentation.main+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", main + "slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", main + "slideLayout+xml"),
            ("/ppt/notesMasters/notesMaster1.xml", main + "notesMaster+xml"),
            ("/ppt/theme/theme1.xml", theme),
            ("/ppt/theme/theme2.xml", theme),
            ("/ppt/presProps.xml", main + "presProps+xml"),
            ("/ppt/viewProps.xml", main + "viewProps+xml"),
            ("/ppt/tableStyles.xml", main + "tableStyles+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml"),
        ]
        for number in stride(from: 1, through: slideCount, by: 1) {
            overrides.append(("/ppt/slides/slide\(number).xml", main + "slide+xml"))
            overrides.append(("/ppt/notesSlides/notesSlide\(number).xml", main + "notesSlide+xml"))
        }
        let entries = overrides.map { entry in
            #"<Override PartName="\#(entry.0)" ContentType="\#(entry.1)"/>"#
        }
        return joined([
            header,
            #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#,
            #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
            #"<Default Extension="xml" ContentType="application/xml"/>"#,
            #"<Default Extension="png" ContentType="image/png"/>"#,
            #"<Default Extension="jpeg" ContentType="image/jpeg"/>"#,
            entries.joined(),
            "</Types>",
        ])
    }

    static let rootRelationships = joined([
        header,
        #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
        #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>"#,
        #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>"#,
        #"<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>"#,
        "</Relationships>",
    ])

    static func core(title: String, date: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        return joined([
            header,
            #"<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">"#,
            "<dc:title>\(escaped(title))</dc:title><dc:creator>InkPad</dc:creator>",
            #"<dcterms:created xsi:type="dcterms:W3CDTF">\#(stamp)</dcterms:created>"#,
            #"<dcterms:modified xsi:type="dcterms:W3CDTF">\#(stamp)</dcterms:modified>"#,
            "</cp:coreProperties>",
        ])
    }

    static func app(slideCount: Int) -> String {
        joined([
            header,
            #"<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">"#,
            "<Application>InkPad</Application><PresentationFormat>Widescreen</PresentationFormat>",
            "<Slides>\(slideCount)</Slides><Notes>\(slideCount)</Notes></Properties>",
        ])
    }

    static func presentation(slideCount: Int) -> String {
        let slides = stride(from: 1, through: slideCount, by: 1).map { number in
            #"<p:sldId id="\#(255 + number)" r:id="rId\#(9 + number)"/>"#
        }
        return joined([
            header,
            #"<p:presentation \#(namespaces) saveSubsetFonts="1">"#,
            #"<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>"#,
            #"<p:notesMasterIdLst><p:notesMasterId r:id="rId2"/></p:notesMasterIdLst>"#,
            "<p:sldIdLst>\(slides.joined())</p:sldIdLst>",
            #"<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/>"#,
            "</p:presentation>",
        ])
    }

    static func presentationRelationships(slideCount: Int) -> String {
        var entries = [
            relationship("rId1", type: "slideMaster", target: "slideMasters/slideMaster1.xml"),
            relationship("rId2", type: "notesMaster", target: "notesMasters/notesMaster1.xml"),
            relationship("rId3", type: "theme", target: "theme/theme1.xml"),
            relationship("rId4", type: "presProps", target: "presProps.xml"),
            relationship("rId5", type: "viewProps", target: "viewProps.xml"),
            relationship("rId6", type: "tableStyles", target: "tableStyles.xml"),
        ]
        for number in stride(from: 1, through: slideCount, by: 1) {
            entries.append(relationship("rId\(9 + number)", type: "slide", target: "slides/slide\(number).xml"))
        }
        return relationships(entries)
    }

    static let presProps = header + #"<p:presentationPr \#(namespaces)/>"#
    static let viewProps = header + #"<p:viewPr \#(namespaces)><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr></p:viewPr>"#
    static let tableStyles = header + #"<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>"#

    static func theme(_ palette: SlidePalette) -> String {
        func color(_ name: String, _ value: SlideColor) -> String {
            #"<a:\#(name)><a:srgbClr val="\#(value.hex)"/></a:\#(name)>"#
        }
        let fill = #"<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>"#
        let line = #"<a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>"#
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        let fonts = #"<a:latin typeface="Helvetica Neue"/><a:ea typeface=""/><a:cs typeface="Geeza Pro"/>"#
        let darkest = palette.background.first ?? SlideColor(0.1, 0.1, 0.14)
        let colors = joined([
            color("dk1", SlideColor(0, 0, 0)),
            color("lt1", SlideColor(1, 1, 1)),
            color("dk2", darkest),
            color("lt2", SlideColor(0.93, 0.93, 0.95)),
            color("accent1", palette.accent),
            color("accent2", palette.glow),
            color("accent3", SlideColor(0.30, 0.32, 0.86)),
            color("accent4", SlideColor(0.98, 0.55, 0.25)),
            color("accent5", SlideColor(0.20, 0.70, 0.45)),
            color("accent6", SlideColor(0.85, 0.25, 0.45)),
            color("hlink", SlideColor(0.04, 0.45, 0.90)),
            color("folHlink", SlideColor(0.55, 0.30, 0.80)),
        ])
        return joined([
            header,
            #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="InkPad">"#,
            #"<a:themeElements><a:clrScheme name="InkPad">\#(colors)</a:clrScheme>"#,
            #"<a:fontScheme name="InkPad"><a:majorFont>\#(fonts)</a:majorFont><a:minorFont>\#(fonts)</a:minorFont></a:fontScheme>"#,
            #"<a:fmtScheme name="InkPad">"#,
            "<a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst>",
            "<a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst>",
            "<a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>",
            "<a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst>",
            "</a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>",
        ])
    }

    static let slideMaster = joined([
        header,
        #"<p:sldMaster \#(namespaces)>"#,
        #"<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\#(emptyGroup)</p:spTree></p:cSld>"#,
        colorMap,
        #"<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>"#,
        #"<p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="4400"/></a:lvl1pPr></p:titleStyle>"#,
        #"<p:bodyStyle><a:lvl1pPr><a:defRPr sz="2800"/></a:lvl1pPr></p:bodyStyle>"#,
        #"<p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle></p:txStyles>"#,
        "</p:sldMaster>",
    ])

    static let slideLayout = joined([
        header,
        #"<p:sldLayout \#(namespaces) type="blank" preserve="1">"#,
        #"<p:cSld name="Blank"><p:spTree>\#(emptyGroup)</p:spTree></p:cSld>"#,
        "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>",
    ])

    static let notesMaster = joined([
        header,
        #"<p:notesMaster \#(namespaces)>"#,
        #"<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\#(emptyGroup)"#,
        #"<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>"#,
        #"<p:spPr><a:xfrm><a:off x="381000" y="685800"/><a:ext cx="6096000" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>"#,
        #"<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>"#,
        #"<p:spPr><a:xfrm><a:off x="685800" y="4343400"/><a:ext cx="5486400" cy="4114800"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>"#,
        #"<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>"#,
        "</p:spTree></p:cSld>",
        colorMap,
        #"<p:notesStyle><a:lvl1pPr marL="0" algn="l"><a:defRPr sz="1200"/></a:lvl1pPr></p:notesStyle>"#,
        "</p:notesMaster>",
    ])

    static func slide(shapes: String, background: [SlideColor]) -> String {
        let first = background.first ?? SlideColor(0.1, 0.1, 0.14)
        let last = background.last ?? first
        return joined([
            header,
            #"<p:sld \#(namespaces)><p:cSld>"#,
            #"<p:bg><p:bgPr><a:gradFill rotWithShape="1"><a:gsLst>"#,
            #"<a:gs pos="0"><a:srgbClr val="\#(first.hex)"/></a:gs><a:gs pos="100000"><a:srgbClr val="\#(last.hex)"/></a:gs>"#,
            #"</a:gsLst><a:lin ang="2700000" scaled="0"/></a:gradFill><a:effectLst/></p:bgPr></p:bg>"#,
            "<p:spTree>\(emptyGroup)\(shapes)</p:spTree></p:cSld>",
            "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>",
        ])
    }

    static func notes(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return #"<a:p><a:endParaRPr lang="en-US"/></a:p>"# }
            let rtl = SlideSymbols.isArabic(trimmed)
            return #"<a:p><a:pPr algn="\#(rtl ? "r" : "l")" rtl="\#(rtl ? 1 : 0)"/><a:r><a:rPr lang="\#(rtl ? "ar-SA" : "en-US")" dirty="0"/><a:t>\#(escaped(trimmed))</a:t></a:r></a:p>"#
        }
        return joined([
            header,
            #"<p:notes \#(namespaces)><p:cSld><p:spTree>\#(emptyGroup)"#,
            #"<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>"#,
            #"<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>"#,
            "<p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs.joined())</p:txBody></p:sp>",
            "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>",
        ])
    }
}
