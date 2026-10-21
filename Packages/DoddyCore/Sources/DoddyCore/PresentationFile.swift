import Foundation

/// Writes a `PresentationDraft` as a PowerPoint file (.pptx, Office Open XML), which Keynote,
/// PowerPoint and Google Slides open (ADR-567). Plain Foundation, so it is tested on Linux and the
/// result can be checked with other tools. 16:9 slides in Brand Guidelines V2.2's paper, ink and
/// orange; text in the theme's fonts (Helvetica Neue, which Keynote has; other apps substitute).
/// No font is embedded and no image is added.
public enum PresentationFile {
    /// Slide size in EMU (914,400 per inch): 13.333 × 7.5 inches.
    static let width = 12_192_000
    static let height = 6_858_000
    static let inch = 914_400

    /// Brand V2.2 (`CandidateColorRole`, light): paper, ink, secondary text, orange.
    static let paper = "FFF7E9"
    static let ink = "171715"
    static let secondary = "655F56"
    static let orange = "FF6A00"

    public static func pptx(_ draft: PresentationDraft, created: Date) throws -> Data {
        try StoredZip.archive(parts(draft, created: created).map { StoredZip.Entry($0.path, Data($0.xml.utf8)) })
    }

    /// Every part of the package, in the order they are written. Internal so tests can read them.
    static func parts(_ draft: PresentationDraft, created: Date) -> [(path: String, xml: String)] {
        let count = draft.slideCount
        var parts: [(path: String, xml: String)] = [
            ("[Content_Types].xml", contentTypes(slides: count)),
            ("_rels/.rels", packageRels),
            ("docProps/core.xml", core(title: draft.title, created: created)),
            ("docProps/app.xml", app(slides: count)),
            ("ppt/presentation.xml", presentation(slides: count)),
            ("ppt/_rels/presentation.xml.rels", presentationRels(slides: count)),
            ("ppt/presProps.xml", presProps),
            ("ppt/viewProps.xml", viewProps),
            ("ppt/tableStyles.xml", tableStyles),
            ("ppt/theme/theme1.xml", theme),
            ("ppt/slideMasters/slideMaster1.xml", slideMaster),
            ("ppt/slideMasters/_rels/slideMaster1.xml.rels", slideMasterRels),
            ("ppt/slideLayouts/slideLayout1.xml", slideLayout),
            ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", slideLayoutRels),
        ]
        parts.append(("ppt/slides/slide1.xml", titleSlide(draft)))
        for (index, slide) in draft.slides.enumerated() {
            parts.append(("ppt/slides/slide\(index + 2).xml", contentSlide(slide)))
        }
        for number in 1...count {
            parts.append(("ppt/slides/_rels/slide\(number).xml.rels", slideRels))
        }
        return parts
    }

    // MARK: Text sizes

    /// Hundredths of a point, as DrawingML writes font sizes.
    static func titleSlideSize(_ title: String) -> Int {
        switch title.count {
        case ...30: 5400
        case ...60: 4400
        default: 3600
        }
    }

    static func slideTitleSize(_ title: String) -> Int {
        switch title.count {
        case ...45: 3600
        case ...90: 2800
        default: 2400
        }
    }

    /// The largest body size whose points fit the body box, estimated from their length (an
    /// average glyph is about half the font size wide). Never below 16 pt.
    static func bodySize(_ points: [String]) -> Int {
        let boxWidth = 825.0   // points: the body box less the bullet indent
        let boxHeight = 340.0
        for size in [28.0, 24.0, 20.0, 18.0] {
            let perLine = max(1, Int(boxWidth / (size * 0.5)))
            let lines = points.reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
            let needed = Double(lines) * size * 1.2 + Double(max(points.count - 1, 0)) * size * 0.6
            if needed <= boxHeight { return Int(size * 100) }
        }
        return 1600
    }

    // MARK: Slides

    static func titleSlide(_ draft: PresentationDraft) -> String {
        var shapes = [
            textBox(id: 2, name: "Title", x: 0.75, y: 1.6, w: 11.83, h: 2.75, anchor: "b",
                    paragraphs: [run(draft.title, size: titleSlideSize(draft.title), bold: true, color: ink, font: "+mj-lt")]),
            rectangle(id: 3, name: "Accent", x: 0.75, y: 4.55, w: 1.2, h: 0.1, color: orange),
        ]
        if let subtitle = draft.subtitle {
            shapes.append(textBox(id: 4, name: "Subtitle", x: 0.75, y: 4.85, w: 11.83, h: 1.5, anchor: "t",
                                  paragraphs: [run(subtitle, size: 2400, bold: false, color: secondary, font: "+mn-lt")]))
        }
        return slide(shapes)
    }

    static func contentSlide(_ content: PresentationSlide) -> String {
        let size = bodySize(content.points)
        let bullets = content.points.map { point in
            "<a:p><a:pPr marL=\"342900\" indent=\"-342900\"><a:spcBef><a:spcPts val=\"\(size * 6 / 10)\"/></a:spcBef>"
                + "<a:buClr><a:srgbClr val=\"\(orange)\"/></a:buClr><a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/></a:pPr>"
                + runBody(point, size: size, bold: false, color: ink, font: "+mn-lt") + "</a:p>"
        }
        var shapes = [
            rectangle(id: 2, name: "Accent", x: 0.75, y: 0.55, w: 0.8, h: 0.08, color: orange),
            textBox(id: 3, name: "Title", x: 0.75, y: 0.75, w: 11.83, h: 1.3, anchor: "t",
                    paragraphs: [run(content.title, size: slideTitleSize(content.title), bold: true, color: ink, font: "+mj-lt")]),
        ]
        if !bullets.isEmpty {
            shapes.append(textBox(id: 4, name: "Points", x: 0.75, y: 2.25, w: 11.83, h: 4.75, anchor: "t", paragraphs: bullets))
        }
        return slide(shapes)
    }

    private static func slide(_ shapes: [String]) -> String {
        xmlHeader + "<p:sld \(namespaces)><p:cSld><p:spTree>" + groupHeader + shapes.joined()
            + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
    }

    private static func emu(_ inches: Double) -> Int { Int((inches * Double(inch)).rounded()) }

    private static func frame(x: Double, y: Double, w: Double, h: Double) -> String {
        "<a:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(emu(w))\" cy=\"\(emu(h))\"/></a:xfrm>"
    }

    private static func rectangle(id: Int, name: String, x: Double, y: Double, w: Double, h: Double, color: String) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>"
            + frame(x: x, y: y, w: w, h: h)
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"
    }

    private static func textBox(id: Int, name: String, x: Double, y: Double, w: Double, h: Double, anchor: String, paragraphs: [String]) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr>"
            + frame(x: x, y: y, w: w, h: h)
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody>"
            + "<a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"\(anchor)\"><a:normAutofit/></a:bodyPr><a:lstStyle/>"
            + paragraphs.joined() + "</p:txBody></p:sp>"
    }

    /// One paragraph holding one run.
    private static func run(_ text: String, size: Int, bold: Bool, color: String, font: String) -> String {
        "<a:p>" + runBody(text, size: size, bold: bold, color: color, font: font) + "</a:p>"
    }

    private static func runBody(_ text: String, size: Int, bold: Bool, color: String, font: String) -> String {
        "<a:r><a:rPr sz=\"\(size)\" b=\"\(bold ? 1 : 0)\" dirty=\"0\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
            + "<a:latin typeface=\"\(font)\"/></a:rPr><a:t>\(escape(text))</a:t></a:r>"
    }

    /// Text for an XML element or attribute: the five special characters escaped, and characters
    /// XML 1.0 can't hold (most control characters) left out.
    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            default:
                let value = scalar.value
                let allowed = value >= 0x20 && !(0xFFFE...0xFFFF).contains(value)
                if allowed { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    // MARK: Package parts

    static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    static let namespaces = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
    static let groupHeader = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    private static let officeRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let presentationML = "application/vnd.openxmlformats-officedocument.presentationml"

    static func contentTypes(slides: Int) -> String {
        var overrides = [
            ("/ppt/presentation.xml", "\(presentationML).presentation.main+xml"),
            ("/ppt/presProps.xml", "\(presentationML).presProps+xml"),
            ("/ppt/viewProps.xml", "\(presentationML).viewProps+xml"),
            ("/ppt/tableStyles.xml", "\(presentationML).tableStyles+xml"),
            ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", "\(presentationML).slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", "\(presentationML).slideLayout+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml"),
        ]
        for number in 1...slides {
            overrides.append(("/ppt/slides/slide\(number).xml", "\(presentationML).slide+xml"))
        }
        return xmlHeader + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + overrides.map { "<Override PartName=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
            + "</Types>"
    }

    private static func relationships(_ items: [(id: String, type: String, target: String)]) -> String {
        xmlHeader + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + items.map { "<Relationship Id=\"\($0.id)\" Type=\"\($0.type)\" Target=\"\($0.target)\"/>" }.joined()
            + "</Relationships>"
    }

    static let packageRels = relationships([
        ("rId1", "\(officeRel)/officeDocument", "ppt/presentation.xml"),
        ("rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml"),
        ("rId3", "\(officeRel)/extended-properties", "docProps/app.xml"),
    ])

    static func core(title: String, created: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: created)
        return xmlHeader + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" "
            + "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
            + "<dc:title>\(escape(title))</dc:title>"
            + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:created>"
            + "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:modified>"
            + "</cp:coreProperties>"
    }

    static func app(slides: Int) -> String {
        xmlHeader + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\">"
            + "<Application>Doddy</Application><PresentationFormat>Widescreen</PresentationFormat><Slides>\(slides)</Slides></Properties>"
    }

    static func presentation(slides: Int) -> String {
        let ids = (1...slides).map { "<p:sldId id=\"\(255 + $0)\" r:id=\"rId\(5 + $0)\"/>" }.joined()
        return xmlHeader + "<p:presentation \(namespaces) saveSubsetFonts=\"1\">"
            + "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>"
            + "<p:sldIdLst>\(ids)</p:sldIdLst>"
            + "<p:sldSz cx=\"\(width)\" cy=\"\(height)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>"
            + "</p:presentation>"
    }

    static func presentationRels(slides: Int) -> String {
        var items: [(id: String, type: String, target: String)] = [
            ("rId1", "\(officeRel)/slideMaster", "slideMasters/slideMaster1.xml"),
            ("rId2", "\(officeRel)/presProps", "presProps.xml"),
            ("rId3", "\(officeRel)/viewProps", "viewProps.xml"),
            ("rId4", "\(officeRel)/theme", "theme/theme1.xml"),
            ("rId5", "\(officeRel)/tableStyles", "tableStyles.xml"),
        ]
        for number in 1...slides {
            items.append(("rId\(5 + number)", "\(officeRel)/slide", "slides/slide\(number).xml"))
        }
        return relationships(items)
    }

    static let presProps = xmlHeader + "<p:presentationPr \(namespaces)/>"
    static let viewProps = xmlHeader + "<p:viewPr \(namespaces)><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"
    static let tableStyles = xmlHeader
        + "<a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"

    static let slideMaster = xmlHeader + "<p:sldMaster \(namespaces)><p:cSld>"
        + "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"\(paper)\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>"
        + "<p:spTree>\(groupHeader)</p:spTree></p:cSld>"
        + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" "
        + "accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
        + "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>"
        + "<p:txStyles>"
        + "<p:titleStyle><a:lvl1pPr><a:defRPr sz=\"3600\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mj-lt\"/></a:defRPr></a:lvl1pPr></p:titleStyle>"
        + "<p:bodyStyle><a:lvl1pPr><a:defRPr sz=\"2400\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl1pPr></p:bodyStyle>"
        + "<p:otherStyle><a:lvl1pPr><a:defRPr sz=\"1800\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl1pPr></p:otherStyle>"
        + "</p:txStyles></p:sldMaster>"

    static let slideMasterRels = relationships([
        ("rId1", "\(officeRel)/slideLayout", "../slideLayouts/slideLayout1.xml"),
        ("rId2", "\(officeRel)/theme", "../theme/theme1.xml"),
    ])

    static let slideLayout = xmlHeader + "<p:sldLayout \(namespaces) type=\"blank\" preserve=\"1\">"
        + "<p:cSld name=\"Blank\"><p:spTree>\(groupHeader)</p:spTree></p:cSld>"
        + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    static let slideLayoutRels = relationships([("rId1", "\(officeRel)/slideMaster", "../slideMasters/slideMaster1.xml")])

    static let slideRels = relationships([("rId1", "\(officeRel)/slideLayout", "../slideLayouts/slideLayout1.xml")])

    static let theme: String = {
        func color(_ name: String, _ hex: String) -> String { "<a:\(name)><a:srgbClr val=\"\(hex)\"/></a:\(name)>" }
        func fonts(_ tag: String) -> String {
            "<a:\(tag)><a:latin typeface=\"Helvetica Neue\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:\(tag)>"
        }
        let solid = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = { (w: Int) in "<a:ln w=\"\(w)\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\">\(solid)<a:prstDash val=\"solid\"/></a:ln>" }
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        return xmlHeader + "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Doddy\"><a:themeElements>"
            + "<a:clrScheme name=\"Doddy\">"
            + color("dk1", ink) + color("lt1", paper) + color("dk2", "26231F") + color("lt2", "F5EAD8")
            + color("accent1", orange) + color("accent2", "A64B00") + color("accent3", "326746")
            + color("accent4", "655F56") + color("accent5", "C5BCAD") + color("accent6", "A3342E")
            + color("hlink", "A64B00") + color("folHlink", "655F56")
            + "</a:clrScheme>"
            + "<a:fontScheme name=\"Doddy\">" + fonts("majorFont") + fonts("minorFont") + "</a:fontScheme>"
            + "<a:fmtScheme name=\"Doddy\">"
            + "<a:fillStyleLst>\(solid)\(solid)\(solid)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(line(6350))\(line(12700))\(line(19050))</a:lnStyleLst>"
            + "<a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(solid)\(solid)\(solid)</a:bgFillStyleLst>"
            + "</a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }()
}
