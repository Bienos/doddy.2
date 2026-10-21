import Foundation

// Translator mode (ADR-214 design, ADR-215 build). A mode of Doddy's own conversation (T2), not a
// separate agent: face to face, both ways, or listen only, one way into the owner's language (T1).
// While it is on, the app refuses every tool call, the conversation is private, and nothing of it
// is kept on the iPhone; the owner may copy the text or save the facts as a note on a tap within
// five minutes of the end (T3). Who is talking is told by language, with hold-to-talk as a fallback
// (T4). The quiet word ("Doddy, …" answered on the owner's half, T5) is off since 21 Oct 2026
// (ADR-567): every line is translated, including ones that name Doddy.
// Native voices per language (T6) wait for a listening pass; this build uses Doddy's voice.

public enum TranslatorKind: String, Equatable, Sendable, CaseIterable {
    /// Both ways, the phone between two people; their half of the screen faces them.
    case faceToFace = "face_to_face"
    /// One way into the owner's language: a guide, a talk, an announcement. Doddy speaks only to the owner.
    case listen
}

/// One of the 37 European languages Doddy speaks (ADR-212), with the lines shown or said to the
/// other person in that language. These lines were written for this build and still need a native
/// speaker's review before release (docs/implementation/TRANSLATOR_STATUS.md).
public struct TranslatorLanguage: Equatable, Hashable, Sendable, Identifiable {
    public let code: String
    public let nativeName: String
    public let englishName: String
    /// Always on their half: "AI translation · may contain mistakes".
    public let aiLabel: String
    /// The disclosure Doddy says to them first, in their language, before translating anything.
    public let hello: String
    /// The hold-to-talk button for a noisy place: "Hold while you speak".
    public let holdToTalk: String
    /// Careful mode, on their half: "AI translation. For anything important, please also get it in writing."
    public let careful: String

    public var id: String { code }

    /// "Español (Spanish)", or just "English".
    public var label: String { nativeName == englishName ? nativeName : "\(nativeName) (\(englishName))" }
}

public enum TranslatorLanguages {
    public static let all: [TranslatorLanguage] = [
        .init(code: "en", nativeName: "English", englishName: "English",
              aiLabel: "AI translation · may contain mistakes",
              hello: "Hi, I'm Doddy, an AI translator on this phone. I'll translate between you two. Please speak normally.",
              holdToTalk: "Hold while you speak",
              careful: "AI translation. For anything important, please also get it in writing."),
        .init(code: "pl", nativeName: "Polski", englishName: "Polish",
              aiLabel: "Tłumaczenie AI · może zawierać błędy",
              hello: "Cześć, jestem Doddy, tłumacz AI na tym telefonie. Będę tłumaczyć między wami. Proszę mówić normalnie.",
              holdToTalk: "Przytrzymaj, gdy mówisz",
              careful: "Tłumaczenie AI. W ważnych sprawach poproś też o to na piśmie."),
        .init(code: "de", nativeName: "Deutsch", englishName: "German",
              aiLabel: "KI-Übersetzung · kann Fehler enthalten",
              hello: "Hallo, ich bin Doddy, ein KI-Übersetzer auf diesem Telefon. Ich übersetze zwischen Ihnen beiden. Sprechen Sie ganz normal.",
              holdToTalk: "Gedrückt halten, während Sie sprechen",
              careful: "KI-Übersetzung. Lassen Sie sich Wichtiges bitte auch schriftlich geben."),
        .init(code: "fr", nativeName: "Français", englishName: "French",
              aiLabel: "Traduction par IA · peut contenir des erreurs",
              hello: "Bonjour, je suis Doddy, un traducteur IA sur ce téléphone. Je vais traduire entre vous deux. Parlez normalement.",
              holdToTalk: "Maintenez pendant que vous parlez",
              careful: "Traduction par IA. Pour tout ce qui est important, demandez-le aussi par écrit."),
        .init(code: "es", nativeName: "Español", englishName: "Spanish",
              aiLabel: "Traducción con IA · puede tener errores",
              hello: "Hola, soy Doddy, un traductor de IA en este teléfono. Traduciré entre ustedes dos. Hable con normalidad.",
              holdToTalk: "Mantenga pulsado mientras habla",
              careful: "Traducción con IA. Para algo importante, pídalo también por escrito."),
        .init(code: "it", nativeName: "Italiano", englishName: "Italian",
              aiLabel: "Traduzione IA · può contenere errori",
              hello: "Ciao, sono Doddy, un traduttore IA su questo telefono. Tradurrò tra voi due. Parlate normalmente.",
              holdToTalk: "Tieni premuto mentre parli",
              careful: "Traduzione IA. Per le cose importanti, chiedetelo anche per iscritto."),
        .init(code: "pt", nativeName: "Português", englishName: "Portuguese",
              aiLabel: "Tradução por IA · pode conter erros",
              hello: "Olá, sou o Doddy, um tradutor de IA neste telemóvel. Vou traduzir entre vocês os dois. Fale normalmente.",
              holdToTalk: "Mantenha premido enquanto fala",
              careful: "Tradução por IA. Para algo importante, peça também por escrito."),
        .init(code: "nl", nativeName: "Nederlands", englishName: "Dutch",
              aiLabel: "AI-vertaling · kan fouten bevatten",
              hello: "Hallo, ik ben Doddy, een AI-vertaler op deze telefoon. Ik vertaal tussen jullie twee. Praat gewoon normaal.",
              holdToTalk: "Ingedrukt houden terwijl je praat",
              careful: "AI-vertaling. Vraag het bij iets belangrijks ook op papier."),
        .init(code: "sv", nativeName: "Svenska", englishName: "Swedish",
              aiLabel: "AI-översättning · kan innehålla fel",
              hello: "Hej, jag är Doddy, en AI-översättare i den här telefonen. Jag översätter mellan er två. Prata som vanligt.",
              holdToTalk: "Håll in medan du pratar",
              careful: "AI-översättning. Be om det skriftligt också när det är viktigt."),
        .init(code: "da", nativeName: "Dansk", englishName: "Danish",
              aiLabel: "AI-oversættelse · kan indeholde fejl",
              hello: "Hej, jeg er Doddy, en AI-oversætter på denne telefon. Jeg oversætter mellem jer to. Tal helt normalt.",
              holdToTalk: "Hold nede, mens du taler",
              careful: "AI-oversættelse. Bed også om det skriftligt, når det er vigtigt."),
        .init(code: "no", nativeName: "Norsk", englishName: "Norwegian",
              aiLabel: "KI-oversettelse · kan inneholde feil",
              hello: "Hei, jeg er Doddy, en KI-oversetter på denne telefonen. Jeg oversetter mellom dere to. Snakk helt vanlig.",
              holdToTalk: "Hold inne mens du snakker",
              careful: "KI-oversettelse. Be om det skriftlig også når det er viktig."),
        .init(code: "fi", nativeName: "Suomi", englishName: "Finnish",
              aiLabel: "Tekoälykäännös · voi sisältää virheitä",
              hello: "Hei, olen Doddy, tekoälykääntäjä tässä puhelimessa. Käännän teidän kahden välillä. Puhukaa normaalisti.",
              holdToTalk: "Pidä painettuna, kun puhut",
              careful: "Tekoälykäännös. Pyydä tärkeät asiat myös kirjallisena."),
        .init(code: "cs", nativeName: "Čeština", englishName: "Czech",
              aiLabel: "Překlad AI · může obsahovat chyby",
              hello: "Dobrý den, jsem Doddy, AI překladatel v tomto telefonu. Budu překládat mezi vámi dvěma. Mluvte normálně.",
              holdToTalk: "Držte, když mluvíte",
              careful: "Překlad AI. U důležitých věcí si to nechte dát i písemně."),
        .init(code: "sk", nativeName: "Slovenčina", englishName: "Slovak",
              aiLabel: "Preklad AI · môže obsahovať chyby",
              hello: "Dobrý deň, som Doddy, AI prekladateľ v tomto telefóne. Budem prekladať medzi vami dvoma. Hovorte normálne.",
              holdToTalk: "Podržte, keď hovoríte",
              careful: "Preklad AI. Pri dôležitých veciach si to vypýtajte aj písomne."),
        .init(code: "hu", nativeName: "Magyar", englishName: "Hungarian",
              aiLabel: "MI-fordítás · tartalmazhat hibákat",
              hello: "Jó napot, Doddy vagyok, MI-fordító ezen a telefonon. Fordítok kettőjük között. Beszéljen nyugodtan, ahogy szokott.",
              holdToTalk: "Tartsa nyomva, amíg beszél",
              careful: "MI-fordítás. Fontos dolgokat kérjen írásban is."),
        .init(code: "ro", nativeName: "Română", englishName: "Romanian",
              aiLabel: "Traducere AI · poate conține greșeli",
              hello: "Bună ziua, sunt Doddy, un traducător AI pe acest telefon. Voi traduce între voi doi. Vorbiți normal.",
              holdToTalk: "Țineți apăsat cât vorbiți",
              careful: "Traducere AI. Pentru lucruri importante, cereți-le și în scris."),
        .init(code: "bg", nativeName: "Български", englishName: "Bulgarian",
              aiLabel: "Превод с ИИ · може да съдържа грешки",
              hello: "Здравейте, аз съм Doddy, преводач с ИИ на този телефон. Ще превеждам между вас двамата. Говорете нормално.",
              holdToTalk: "Задръжте, докато говорите",
              careful: "Превод с ИИ. За важни неща поискайте и писмено."),
        .init(code: "el", nativeName: "Ελληνικά", englishName: "Greek",
              aiLabel: "Μετάφραση ΤΝ · μπορεί να έχει λάθη",
              hello: "Γεια σας, είμαι ο Doddy, ένας μεταφραστής ΤΝ σε αυτό το τηλέφωνο. Θα μεταφράζω ανάμεσα σε εσάς τους δύο. Μιλήστε κανονικά.",
              holdToTalk: "Κρατήστε πατημένο όσο μιλάτε",
              careful: "Μετάφραση ΤΝ. Για κάτι σημαντικό, ζητήστε το και γραπτώς."),
        .init(code: "hr", nativeName: "Hrvatski", englishName: "Croatian",
              aiLabel: "AI prijevod · može sadržavati pogreške",
              hello: "Dobar dan, ja sam Doddy, AI prevoditelj na ovom telefonu. Prevodit ću između vas dvoje. Govorite normalno.",
              holdToTalk: "Držite dok govorite",
              careful: "AI prijevod. Za važne stvari zatražite i pisanu potvrdu."),
        .init(code: "sl", nativeName: "Slovenščina", englishName: "Slovenian",
              aiLabel: "Prevod z UI · lahko vsebuje napake",
              hello: "Pozdravljeni, sem Doddy, prevajalnik z UI na tem telefonu. Prevajal bom med vama. Govorite normalno.",
              holdToTalk: "Pridržite, ko govorite",
              careful: "Prevod z UI. Za pomembne stvari prosite tudi za pisno obliko."),
        .init(code: "lv", nativeName: "Latviešu", englishName: "Latvian",
              aiLabel: "MI tulkojums · var saturēt kļūdas",
              hello: "Labdien, es esmu Doddy, MI tulks šajā telefonā. Es tulkošu starp jums abiem. Runājiet kā parasti.",
              holdToTalk: "Turiet nospiestu, kamēr runājat",
              careful: "MI tulkojums. Svarīgām lietām lūdziet to arī rakstiski."),
        .init(code: "lt", nativeName: "Lietuvių", englishName: "Lithuanian",
              aiLabel: "DI vertimas · gali būti klaidų",
              hello: "Laba diena, aš Doddy, DI vertėjas šiame telefone. Versiu tarp jūsų dviejų. Kalbėkite įprastai.",
              holdToTalk: "Laikykite paspaudę, kol kalbate",
              careful: "DI vertimas. Svarbius dalykus paprašykite ir raštu."),
        .init(code: "uk", nativeName: "Українська", englishName: "Ukrainian",
              aiLabel: "Переклад ШІ · можливі помилки",
              hello: "Вітаю, я Doddy, перекладач ШІ на цьому телефоні. Я перекладатиму між вами двома. Говоріть звичайно.",
              holdToTalk: "Утримуйте, поки говорите",
              careful: "Переклад ШІ. Важливе попросіть також письмово."),
        .init(code: "ru", nativeName: "Русский", englishName: "Russian",
              aiLabel: "Перевод ИИ · возможны ошибки",
              hello: "Здравствуйте, я Doddy, переводчик ИИ на этом телефоне. Я буду переводить между вами. Говорите как обычно.",
              holdToTalk: "Удерживайте, пока говорите",
              careful: "Перевод ИИ. Важное попросите также письменно."),
        .init(code: "tr", nativeName: "Türkçe", englishName: "Turkish",
              aiLabel: "Yapay zekâ çevirisi · hata içerebilir",
              hello: "Merhaba, ben Doddy, bu telefondaki yapay zekâ çevirmeniyim. İkiniz arasında çeviri yapacağım. Normal konuşun.",
              holdToTalk: "Konuşurken basılı tutun",
              careful: "Yapay zekâ çevirisi. Önemli şeyleri yazılı olarak da isteyin."),
        .init(code: "et", nativeName: "Eesti", englishName: "Estonian",
              aiLabel: "Tehisintellekti tõlge · võib sisaldada vigu",
              hello: "Tere, mina olen Doddy, tehisintellektil põhinev tõlk selles telefonis. Tõlgin teie kahe vahel. Rääkige tavaliselt.",
              holdToTalk: "Hoidke all, kui räägite",
              careful: "Tehisintellekti tõlge. Olulised asjad küsige ka kirjalikult."),
        .init(code: "ca", nativeName: "Català", englishName: "Catalan",
              aiLabel: "Traducció amb IA · pot tenir errors",
              hello: "Hola, sóc en Doddy, un traductor d'IA en aquest telèfon. Traduiré entre vosaltres dos. Parleu amb normalitat.",
              holdToTalk: "Manteniu premut mentre parleu",
              careful: "Traducció amb IA. Per a coses importants, demaneu-ho també per escrit."),
        .init(code: "sr", nativeName: "Srpski", englishName: "Serbian",
              aiLabel: "AI prevod · može sadržati greške",
              hello: "Dobar dan, ja sam Doddy, AI prevodilac na ovom telefonu. Prevodiću između vas dvoje. Govorite normalno.",
              holdToTalk: "Držite dok govorite",
              careful: "AI prevod. Za važne stvari tražite i pisanu potvrdu."),
        .init(code: "is", nativeName: "Íslenska", englishName: "Icelandic",
              aiLabel: "Gervigreindarþýðing · getur innihaldið villur",
              hello: "Halló, ég er Doddy, gervigreindartúlkur í þessum síma. Ég túlka á milli ykkar. Talið eðlilega.",
              holdToTalk: "Haltu inni á meðan þú talar",
              careful: "Gervigreindarþýðing. Biddu líka um mikilvæg atriði skriflega."),
        .init(code: "ga", nativeName: "Gaeilge", englishName: "Irish",
              aiLabel: "Aistriúchán AI · d'fhéadfadh botúin a bheith ann",
              hello: "Dia duit, is mise Doddy, aistritheoir AI ar an bhfón seo. Aistreoidh mé eadraibh. Labhair go nádúrtha.",
              holdToTalk: "Coinnigh brúite agus tú ag caint",
              careful: "Aistriúchán AI. Maidir le rud tábhachtach, iarr i scríbhinn é freisin."),
        .init(code: "mt", nativeName: "Malti", englishName: "Maltese",
              aiLabel: "Traduzzjoni bl-IA · jista' jkun fiha żbalji",
              hello: "Bonġu, jien Doddy, traduttur tal-IA fuq dan it-telefon. Se nittraduċi bejnietkom it-tnejn. Tkellmu normali.",
              holdToTalk: "Żomm magħfus waqt li titkellem",
              careful: "Traduzzjoni bl-IA. Għal affarijiet importanti, itlob ukoll bil-miktub."),
        .init(code: "mk", nativeName: "Македонски", englishName: "Macedonian",
              aiLabel: "Превод со ВИ · може да има грешки",
              hello: "Здраво, јас сум Doddy, преведувач со ВИ на овој телефон. Ќе преведувам меѓу вас двајца. Зборувајте нормално.",
              holdToTalk: "Држете додека зборувате",
              careful: "Превод со ВИ. За важни работи, побарајте и писмено."),
        .init(code: "bs", nativeName: "Bosanski", englishName: "Bosnian",
              aiLabel: "AI prijevod · može sadržavati greške",
              hello: "Dobar dan, ja sam Doddy, AI prevodilac na ovom telefonu. Prevodit ću između vas dvoje. Govorite normalno.",
              holdToTalk: "Držite dok govorite",
              careful: "AI prijevod. Za važne stvari tražite i pisanu potvrdu."),
        .init(code: "be", nativeName: "Беларуская", englishName: "Belarusian",
              aiLabel: "Пераклад ШІ · магчымыя памылкі",
              hello: "Добры дзень, я Doddy, перакладчык ШІ на гэтым тэлефоне. Я буду перакладаць паміж вамі. Гаварыце як звычайна.",
              holdToTalk: "Утрымлівайце, пакуль гаворыце",
              careful: "Пераклад ШІ. Важнае папрасіце таксама пісьмова."),
        .init(code: "cy", nativeName: "Cymraeg", englishName: "Welsh",
              aiLabel: "Cyfieithiad AI · gall gynnwys camgymeriadau",
              hello: "Helo, Doddy ydw i, cyfieithydd AI ar y ffôn hwn. Bydda i'n cyfieithu rhwng y ddau ohonoch chi. Siaradwch yn naturiol.",
              holdToTalk: "Daliwch i lawr wrth siarad",
              careful: "Cyfieithiad AI. Am rywbeth pwysig, gofynnwch amdano'n ysgrifenedig hefyd."),
        .init(code: "gl", nativeName: "Galego", englishName: "Galician",
              aiLabel: "Tradución con IA · pode ter erros",
              hello: "Ola, son Doddy, un tradutor de IA neste teléfono. Traducirei entre vós os dous. Fale con normalidade.",
              holdToTalk: "Manteña premido mentres fala",
              careful: "Tradución con IA. Para algo importante, pídao tamén por escrito."),
        .init(code: "lb", nativeName: "Lëtzebuergesch", englishName: "Luxembourgish",
              aiLabel: "KI-Iwwersetzung · ka Feeler hunn",
              hello: "Moien, ech sinn den Doddy, en KI-Iwwersetzer op dësem Telefon. Ech iwwersetzen tëscht Iech zwee. Schwätzt ganz normal.",
              holdToTalk: "Gedréckt halen, während Dir schwätzt",
              careful: "KI-Iwwersetzung. Fir eppes Wichteges, frot et och schrëftlech."),
    ]

    private static let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// A two-letter code, case-insensitive ("nb" and "nn" are read as Norwegian). Nil when Doddy doesn't speak it.
    public static func named(_ code: String) -> TranslatorLanguage? {
        let key = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "nb" || key == "nn" { return byCode["no"] }
        return byCode[key]
    }

    public static var english: TranslatorLanguage { byCode["en"]! }

    /// The owner's language when they didn't say: the starting language from Settings, else the
    /// iPhone's language, else English.
    public static func ownerDefault(settingCode: String?, deviceCode: String?) -> TranslatorLanguage {
        settingCode.flatMap(named) ?? deviceCode.flatMap(named) ?? english
    }

    /// What Home › Translate shows before the owner picks (ADR-567): the two languages used last
    /// time, so a second go is one tap. The first time: the owner's default, and for them English,
    /// or Polish when the owner speaks English. "Detect" made the first sentence wait for a guess,
    /// so it is only the default when it was the last choice. `lastOther` is a code or "detect".
    public static func startingPair(lastOwner: String?, lastOther: String?, ownerDefault: TranslatorLanguage)
        -> (owner: TranslatorLanguage, other: TranslatorLanguage?) {
        let owner = lastOwner.flatMap(named) ?? ownerDefault
        if lastOther?.lowercased() == detectCode { return (owner, nil) }
        if let last = lastOther.flatMap(named), last != owner { return (owner, last) }
        return (owner, owner == english ? byCode["pl"] : english)
    }

    /// Stored for "Detect when they talk".
    public static let detectCode = "detect"
}

/// The two languages and the way of translating, as the owner confirmed them.
public struct TranslatorSetup: Equatable, Sendable {
    public let kind: TranslatorKind
    public let owner: TranslatorLanguage
    /// Nil until Doddy hears them ("Detect when they talk").
    public var other: TranslatorLanguage?

    public init?(kind: TranslatorKind, owner: TranslatorLanguage, other: TranslatorLanguage?) {
        guard owner != other else { return nil }
        self.kind = kind
        self.owner = owner
        self.other = other
    }

    /// "Polski ⇄ Español", "Italiano → Polski", "? ⇄ Polski" while their language is unknown.
    public var pairText: String {
        let theirs = other?.nativeName ?? "?"
        switch kind {
        case .faceToFace: return "\(owner.nativeName) ⇄ \(theirs)"
        case .listen: return "\(theirs) → \(owner.nativeName)"
        }
    }

    /// "PL ⇄ ES" for the middle bar.
    public var codesText: String {
        let theirs = other?.code.uppercased() ?? "?"
        return kind == .faceToFace ? "\(owner.code.uppercased()) ⇄ \(theirs)" : "\(theirs) → \(owner.code.uppercased())"
    }

    /// What the agent hears about the mode, in the `translator_start` variable or the tool reply.
    public var agentDescription: String {
        let theirs = other.map { "\($0.englishName) (\($0.code))" } ?? "not known yet: detect it when they speak"
        switch kind {
        case .faceToFace:
            return "face to face. The user speaks \(owner.englishName) (\(owner.code)); the other person speaks \(theirs)."
        case .listen:
            return "listen only. Translate what is said around the user, in \(theirs), into \(owner.englishName) (\(owner.code)) for the user only."
        }
    }
}

/// The `{{translator_start}}` variable: "none" for a normal conversation, or the mode when the
/// conversation was opened from Home's Translate (then no notes, conversations or profile are sent).
public enum TranslatorPrompt {
    public static let variableName = "translator_start"

    public static func render(_ preset: TranslatorSetup?) -> String {
        guard let preset else { return "none" }
        var text = "Translator mode is on from the start: \(preset.agentDescription)"
        if preset.kind == .faceToFace, let other = preset.other {
            text += " When the app says so, first say exactly this to them, in \(other.englishName): \"\(other.hello)\""
        }
        return text
    }
}

/// The mode requested by `start_translator`, started directly after the user's request.
public struct TranslatorProposal: Equatable, Sendable {
    public let kind: TranslatorKind
    /// Nil: the owner's default (Settings, then the iPhone's language).
    public let yours: TranslatorLanguage?
    /// Nil: detect when they speak.
    public let theirs: TranslatorLanguage?

    public init(kind: TranslatorKind, yours: TranslatorLanguage?, theirs: TranslatorLanguage?) {
        self.kind = kind
        self.yours = yours
        self.theirs = theirs
    }

    /// Nil when both sides would be the same language.
    public func setup(ownerDefault: TranslatorLanguage) -> TranslatorSetup? {
        TranslatorSetup(kind: kind, owner: yours ?? ownerDefault, other: theirs)
    }
}

extension VoiceToolName {
    /// Starts translator mode (ADR-215) after the user asks for translation.
    public static let startTranslator = "start_translator"
    /// Ends translator mode. Harmless, so it runs without a card.
    public static let stopTranslator = "stop_translator"
}

extension VoiceToolRequest {
    static func parseStartTranslator(_ args: Arguments, name: String) -> VoiceToolRequest {
        var kind = TranslatorKind.faceToFace
        if let raw = args.text("mode")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            guard let parsed = TranslatorKind(rawValue: raw) else {
                return .invalid(name: name, reason: "mode must be face_to_face or listen")
            }
            kind = parsed
        }
        guard let theirRaw = args.text("their_language") else {
            return .invalid(name: name, reason: "missing their_language (a language code, or detect)")
        }
        var theirs: TranslatorLanguage?
        if theirRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "detect" {
            guard let language = TranslatorLanguages.named(theirRaw) else {
                return .invalid(name: name, reason: "their_language must be one of Doddy's 37 language codes, or detect")
            }
            theirs = language
        }
        var yours: TranslatorLanguage?
        if let yourRaw = args.text("your_language") {
            guard let language = TranslatorLanguages.named(yourRaw) else {
                return .invalid(name: name, reason: "your_language must be one of Doddy's 37 language codes")
            }
            yours = language
        }
        if let yours, yours == theirs {
            return .invalid(name: name, reason: "the two languages are the same")
        }
        return .startTranslator(TranslatorProposal(kind: kind, yours: yours, theirs: theirs))
    }
}

/// While translator mode is on, the app runs no tool: no notes, reminders, calendar, contacts,
/// accounts or web. Only stop_translator is answered.
public enum TranslatorPolicy {
    public static func allows(_ request: VoiceToolRequest) -> Bool {
        if case .stopTranslator = request { return true }
        return false
    }
}

extension VoiceToolReply {
    /// The user tapped Start. The agent switches into the mode and says the disclosure first.
    public static func translatorStarted(_ setup: TranslatorSetup) -> String {
        var lines = ["started: translator mode is on, \(setup.agentDescription) From now on follow the Translator mode rules: translate, never answer; the app runs no tools until it ends."]
        switch (setup.kind, setup.other) {
        case (.faceToFace, let other?):
            lines.append("First say exactly this to them, in \(other.englishName): \"\(other.hello)\" Then translate every turn.")
        case (.faceToFace, nil):
            lines.append("Their language isn't known yet. Tell the user in one short sentence, in \(setup.owner.englishName), to let them say something first. When they first speak, say the AI translator disclosure to them in their language before anything else, then translate.")
        case (.listen, _):
            lines.append("Say nothing to anyone else. Translate each thing you hear into \(setup.owner.englishName) for the user, one short line at a time.")
        }
        return lines.joined(separator: " ")
    }

    public static let translatorDeclined = "declined: the user chose not to start translating. Nothing changed; talk normally."
    public static let translatorStopped = "stopped: translator mode is off. Nothing from it is kept on the iPhone. Talk with the user normally again; tools work again."
    public static let translatorNotOn = "stopped: translator mode wasn't on. Nothing changed."

    /// Any tool asked for while translating. The tool's name is the agent's own text, so it
    /// follows as data (ToolData).
    public static func translatorRefused(_ name: String) -> String {
        "refused: translator mode is on, so the app doesn't run the tool below or any other tool. Nothing was looked up, saved or changed. Keep translating; the user can end translator mode on screen or by saying stop translating.\n"
            + ToolData.block([quoted("Tool", name)])
    }
}

/// Which way a translated line goes.
public enum TranslatorDirection: Equatable, Sendable {
    /// Said aloud to the other person and written on their half.
    case toOther
    /// Written on the owner's half (and said aloud in the owner's language).
    case toOwner
}

public enum TranslatorRoute: Equatable, Sendable {
    case translation(TranslatorDirection)
    /// The owner started with "Doddy, …": a quiet word, answered on the owner's half only (T5).
    case aside
}

/// Tells which of two languages a line is in, from its script, its letters and its most common words.
/// A guess for routing lines to a half of the screen, never for what Doddy says. Nil when it can't tell.
public enum LanguageGuess {
    public static func guess(_ text: String, among candidates: [TranslatorLanguage]) -> TranslatorLanguage? {
        guard !candidates.isEmpty else { return nil }
        let scored = candidates.map { ($0, score(text, $0.code)) }.sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 > 0 else { return nil }
        if scored.count > 1, scored[1].1 == best.1 { return nil }
        return best.0
    }

    static func score(_ text: String, _ code: String) -> Int {
        let lower = text.lowercased()
        let script = Script.of(lower)
        let profile = profiles[code] ?? Profile(script: .latin, letters: "", words: [])
        if script != .unknown, script != profile.script, !(code == "sr" && script == .cyrillic) { return 0 }
        var points = script == profile.script && script != .latin ? 3 : 0
        points += lower.unicodeScalars.filter { profile.letters.unicodeScalars.contains($0) }.count
        let words = lower.split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
        points += 2 * words.filter { profile.words.contains($0) }.count
        return points
    }

    enum Script: Equatable { case latin, cyrillic, greek, unknown
        static func of(_ text: String) -> Script {
            var latin = 0, cyrillic = 0, greek = 0
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                switch scalar.value {
                case 0x0400...0x04FF: cyrillic += 1
                case 0x0370...0x03FF, 0x1F00...0x1FFF: greek += 1
                case 0x0041...0x024F: latin += 1
                default: break
                }
            }
            let top = max(latin, cyrillic, greek)
            if top == 0 { return .unknown }
            return top == cyrillic ? .cyrillic : top == greek ? .greek : .latin
        }
    }

    struct Profile {
        let script: Script
        /// Letters that point to this language among European ones.
        let letters: String
        let words: Set<String>
    }

    static let profiles: [String: Profile] = [
        "en": .init(script: .latin, letters: "", words: ["the", "and", "is", "are", "you", "what", "this", "that", "please", "where", "how", "much", "i", "my", "it's", "thank", "would", "with"]),
        "pl": .init(script: .latin, letters: "ąćęłńśźż", words: ["jest", "nie", "się", "że", "czy", "jak", "co", "ja", "proszę", "gdzie", "ile", "mnie", "pan", "pani", "dziękuję", "mam", "to", "na", "być", "dobrze", "tak", "dobry", "bardzo", "już", "tutaj"]),
        "de": .init(script: .latin, letters: "äöüß", words: ["der", "die", "das", "und", "ist", "nicht", "ich", "sie", "wir", "ein", "eine", "bitte", "wo", "wie", "was", "haben", "danke", "zu", "mit", "gut", "ja", "nein", "hier"]),
        "fr": .init(script: .latin, letters: "çèêëîïôûœ", words: ["le", "la", "les", "et", "est", "je", "vous", "pas", "une", "un", "des", "que", "où", "combien", "merci", "bonjour", "c'est", "avec", "pour", "oui", "non", "bien", "très", "ici"]),
        "es": .init(script: .latin, letters: "ñ¿¡", words: ["el", "la", "los", "las", "y", "es", "que", "de", "por", "favor", "dónde", "cuánto", "usted", "gracias", "hola", "está", "necesito", "con", "para", "bien", "sí", "bueno", "muy", "aquí", "vale"]),
        "it": .init(script: .latin, letters: "ìò", words: ["il", "lo", "gli", "e", "è", "che", "di", "non", "per", "sono", "dove", "quanto", "grazie", "ciao", "questo", "con", "una", "sì", "bene", "molto", "qui"]),
        "pt": .init(script: .latin, letters: "ãõ", words: ["o", "os", "as", "e", "é", "que", "de", "não", "você", "obrigado", "obrigada", "onde", "quanto", "está", "um", "uma", "com", "para"]),
        "nl": .init(script: .latin, letters: "", words: ["de", "het", "een", "en", "is", "niet", "ik", "je", "wij", "dat", "waar", "hoeveel", "bedankt", "alstublieft", "graag", "met", "voor"]),
        "sv": .init(script: .latin, letters: "åäö", words: ["och", "är", "jag", "du", "det", "en", "ett", "inte", "var", "hur", "mycket", "tack", "vad", "med", "för"]),
        "da": .init(script: .latin, letters: "æøå", words: ["og", "er", "jeg", "du", "det", "en", "et", "ikke", "hvor", "meget", "tak", "hvad", "med", "til"]),
        "no": .init(script: .latin, letters: "æøå", words: ["og", "er", "jeg", "du", "det", "en", "et", "ikke", "hvor", "mye", "takk", "hva", "med", "til"]),
        "fi": .init(script: .latin, letters: "äö", words: ["ja", "on", "minä", "sinä", "se", "ei", "mitä", "missä", "kiitos", "paljonko", "olen", "että", "kanssa"]),
        "cs": .init(script: .latin, letters: "ěčřšžůý", words: ["je", "a", "se", "na", "to", "že", "jak", "kde", "kolik", "děkuji", "prosím", "nevím", "jsem", "mám"]),
        "sk": .init(script: .latin, letters: "äčďľĺňôŕšťž", words: ["je", "a", "sa", "na", "to", "že", "ako", "kde", "koľko", "ďakujem", "prosím", "som", "mám"]),
        "hu": .init(script: .latin, letters: "őű", words: ["a", "az", "és", "hogy", "nem", "van", "ez", "mi", "hol", "mennyi", "köszönöm", "kérem", "igen", "egy"]),
        "ro": .init(script: .latin, letters: "ăâîșțşţ", words: ["și", "este", "nu", "de", "la", "un", "o", "ce", "unde", "cât", "mulțumesc", "vă", "sunt", "cu"]),
        "bg": .init(script: .cyrillic, letters: "ъщ", words: ["и", "е", "не", "на", "да", "ли", "как", "къде", "колко", "благодаря", "това", "съм", "със"]),
        "el": .init(script: .greek, letters: "", words: ["και", "είναι", "δεν", "το", "η", "ο", "που", "πόσο", "ευχαριστώ", "παρακαλώ", "να"]),
        "hr": .init(script: .latin, letters: "čćđšž", words: ["je", "i", "se", "na", "da", "što", "gdje", "koliko", "hvala", "molim", "nije", "sam"]),
        "sl": .init(script: .latin, letters: "čšž", words: ["je", "in", "se", "na", "da", "kaj", "kje", "koliko", "hvala", "prosim", "ni", "sem"]),
        "lv": .init(script: .latin, letters: "āēģīķļņū", words: ["ir", "un", "es", "tu", "ne", "kur", "cik", "paldies", "lūdzu", "kas", "ar"]),
        "lt": .init(script: .latin, letters: "ąėįųū", words: ["ir", "yra", "aš", "tu", "ne", "kur", "kiek", "ačiū", "prašau", "kas", "su"]),
        "uk": .init(script: .cyrillic, letters: "іїєґ", words: ["і", "що", "це", "як", "де", "скільки", "дякую", "будь", "ласка", "не", "я", "ви"]),
        "ru": .init(script: .cyrillic, letters: "ыэё", words: ["и", "что", "это", "как", "где", "сколько", "спасибо", "пожалуйста", "не", "я", "вы", "мне"]),
        "tr": .init(script: .latin, letters: "ğış", words: ["ve", "bir", "bu", "ne", "nerede", "kaç", "teşekkür", "lütfen", "değil", "ben", "siz", "mi", "var"]),
        "et": .init(script: .latin, letters: "õ", words: ["ja", "on", "ma", "sa", "see", "ei", "kus", "kui", "palju", "aitäh", "palun", "mis"]),
        "ca": .init(script: .latin, letters: "·", words: ["el", "la", "els", "les", "i", "és", "que", "de", "no", "on", "quant", "gràcies", "si", "us", "plau", "amb"]),
        "sr": .init(script: .latin, letters: "čćđšžђћјљњџ", words: ["je", "i", "se", "na", "da", "šta", "gde", "koliko", "hvala", "molim", "nije", "sam", "шта", "где", "хвала"]),
        "is": .init(script: .latin, letters: "ðþæ", words: ["og", "er", "ég", "þú", "það", "ekki", "hvar", "hvað", "takk", "við"]),
        "ga": .init(script: .latin, letters: "", words: ["agus", "is", "tá", "an", "na", "ní", "cá", "conas", "go", "raibh", "maith", "agat", "dia"]),
        "mt": .init(script: .latin, letters: "ċġħ", words: ["u", "huwa", "hija", "il", "ma", "jien", "int", "fejn", "kemm", "grazzi", "jekk"]),
        "mk": .init(script: .cyrillic, letters: "ќѓѕљњџј", words: ["и", "е", "не", "на", "да", "што", "каде", "колку", "благодарам", "ова", "сум"]),
        "bs": .init(script: .latin, letters: "čćđšž", words: ["je", "i", "se", "na", "da", "šta", "gdje", "koliko", "hvala", "molim", "nije", "sam"]),
        "be": .init(script: .cyrillic, letters: "ўі", words: ["і", "што", "гэта", "як", "дзе", "колькі", "дзякуй", "калі", "ласка", "не", "я"]),
        "cy": .init(script: .latin, letters: "ŵŷ", words: ["ac", "yn", "y", "mae", "dw", "chi", "ble", "faint", "diolch", "os", "gwelwch"]),
        "gl": .init(script: .latin, letters: "ñ", words: ["o", "os", "as", "e", "é", "que", "de", "non", "onde", "canto", "grazas", "ola", "vostede"]),
        "lb": .init(script: .latin, letters: "ë", words: ["an", "ass", "net", "ech", "du", "mir", "wou", "wéi", "vill", "merci", "mat"]),
    ]
}

/// Sends each of Doddy's lines to a half of the screen. The translation's own language decides;
/// then the language of what was said before it (a translation goes the other way); then the side
/// held down in a noisy place; then the opposite of the last line.
public struct TranslatorRouter: Sendable {
    public private(set) var setup: TranslatorSetup
    private var last: TranslatorDirection?

    public init(setup: TranslatorSetup) {
        self.setup = setup
    }

    /// Was this a quiet word for Doddy only? Never, since 21 Oct 2026 (owner: "it answers what I'm
    /// saying instead of translating it", ADR-567). It used to be "Doddy, …" or "hey Doddy …" at the
    /// start, but people say his name while talking through him ("Yo, Doddy, I want to tell you
    /// something"), and then nothing was translated. Every line is translated now; the screen's
    /// quiet-word card stays unused until it gets a trigger nobody says by accident.
    public static func isAside(_ said: String?) -> Bool {
        false
    }

    /// `isAside`, unless it was the other person: their hold-to-talk button was held, or what was
    /// said is in a language other than the owner's.
    public func isOwnerAside(_ said: String?, held: TranslatorDirection? = nil) -> Bool {
        guard Self.isAside(said), let said, held != .toOther else { return false }
        return (languageOf(said) ?? setup.owner) == setup.owner
    }

    /// Their language was "detect": the first line not in the owner's language sets it.
    public mutating func learnTheirLanguage(from said: String) -> TranslatorLanguage? {
        guard setup.other == nil else { return nil }
        let others = TranslatorLanguages.all.filter { $0 != setup.owner }
        guard let found = LanguageGuess.guess(said, among: others),
              LanguageGuess.score(said, found.code) > LanguageGuess.score(said, setup.owner.code)
        else { return nil }
        setup.other = found
        return found
    }

    /// `held` is the side held down on a hold-to-talk button for what was said, if any.
    public mutating func route(agentLine: String, after said: String?, held: TranslatorDirection? = nil) -> TranslatorRoute {
        if isOwnerAside(said, held: held) { return .aside }
        guard setup.kind == .faceToFace else { return .translation(.toOwner) }
        let direction = guessDirection(agentLine, said: said, held: held)
        last = direction
        return .translation(direction)
    }

    private func guessDirection(_ line: String, said: String?, held: TranslatorDirection?) -> TranslatorDirection {
        if let lang = languageOf(line) { return lang == setup.owner ? .toOwner : .toOther }
        if let said, let lang = languageOf(said) { return lang == setup.owner ? .toOther : .toOwner }
        // Held "I'm speaking" on the owner's side: what follows is for them.
        if let held { return held == .toOwner ? .toOther : .toOwner }
        switch last {
        case .toOther: return .toOwner
        case .toOwner, nil: return .toOther
        }
    }

    private func languageOf(_ text: String) -> TranslatorLanguage? {
        if let other = setup.other { return LanguageGuess.guess(text, among: [setup.owner, other]) }
        // Their language not known yet: anything clearly not the owner's is theirs.
        let others = TranslatorLanguages.all.filter { $0 != setup.owner }
        guard let found = LanguageGuess.guess(text, among: others) else { return nil }
        return LanguageGuess.score(text, found.code) > LanguageGuess.score(text, setup.owner.code) ? found : setup.owner
    }
}

/// Prices, times, numbers with units, phone numbers and street addresses, copied exactly as written
/// so both halves show them as cards. Order of appearance, no repeats, at most four.
public enum ExactFacts {
    public static let limit = 4

    private static let patterns: [String] = [
        // Prices: €12, 12 €, 12,50 zł, 40 PLN, £3.20, 15 Kč.
        #"(?:[€$£₴₽₺]\s?\d+(?:[.,]\d{1,2})?)|(?:\d+(?:[.,]\d{1,2})?\s?(?:€|\$|£|zł|PLN|EUR|USD|GBP|CHF|SEK|NOK|DKK|CZK|Kč|HUF|Ft|RON|lei|лв|₴|₽|TL|₺|kr)(?![\p{L}]))"#,
        // Times: 15:30, 9.45, 7h30.
        #"(?<![\d.,:])(?:[01]?\d|2[0-3])(?::|h)[0-5]\d(?![\d])"#,
        // Phone numbers: +48 600 100 200.
        #"\+\d[\d\s-]{7,}\d"#,
        // Street and number: Calle Mayor 12, ul. Długa 5a, Rue de Rivoli 99, na Piotrkowska 120. A
        // one-word name needs "ul." or a word before it, so a sentence's first word ("At 15", "Okay. Wait 10") isn't one.
        #"(?:\b(?:ul\.|al\.|pl\.|St\.|Św\.|Av\.)\s?(?:\p{Lu}[\p{L}'’-]+\s(?:(?:de|del|la|di|da|du|von|van|der)\s)?){1,3}|(?:\p{Lu}[\p{L}'’-]+\s(?:(?:de|del|la|di|da|du|von|van|der)\s)?){2,3}|(?<=[\p{Ll}\d,;:]\s)\p{Lu}[\p{L}'’-]+\s)\d{1,4}[a-zA-Z]?\b"#,
        // Numbers with a unit: 8 h, 500 mg, 2 km, 20%.
        #"\b\d+(?:[.,]\d+)?\s?(?:mg|ml|kg|km|g|l|m|h|min|%|°C)(?![\p{L}])"#,
    ]

    private static let compiled: [NSRegularExpression] = patterns.compactMap { try? NSRegularExpression(pattern: $0) }

    public static func extract(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [(Int, Int, String)] = []
        for regex in compiled {
            for match in regex.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let value = text[swiftRange].trimmingCharacters(in: .whitespaces)
                let start = match.range.location, end = match.range.location + match.range.length
                // A longer fact already covers this one (a time inside an address, a number inside a price).
                if found.contains(where: { $0.0 <= start && end <= $0.1 }) { continue }
                found.removeAll { start <= $0.0 && $0.1 <= end }
                found.append((start, end, value))
            }
        }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map(\.2).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}

/// Health, law, police and money words in any of Doddy's languages. Once one is heard, careful
/// mode stays on until the end: word for word, doubt marked, and both halves suggest writing it
/// down or a professional interpreter. A word list, so it can miss a topic; the prompt also asks
/// the agent to be careful on these topics.
public enum CarefulTopics {
    public enum Topic: String, Equatable, Sendable {
        case health, law, money

        /// The owner's banner text.
        public var banner: String {
            switch self {
            case .health: "Health words. Doddy translates word for word and marks anything he isn't sure of. For anything important, ask for it in writing or a professional interpreter."
            case .law: "Legal or police words. Doddy translates word for word and marks anything he isn't sure of. For anything important, ask for it in writing, a lawyer or a professional interpreter."
            case .money: "Money words. Doddy translates word for word and marks anything he isn't sure of. Check amounts in writing before you agree to anything."
            }
        }
    }

    /// Word beginnings, lowercased.
    static let stems: [Topic: [String]] = [
        .health: [
            "doctor", "hospital", "medic", "pill", "allerg", "ambulanc", "pregnan", "prescription", "symptom", "injur",
            "lekarz", "szpital", "tablet", "alergi", "karetk", "ciąż", "recept", "chor",
            "arzt", "ärzt", "krankenhaus", "medikament", "schmerz", "schwanger", "rezept",
            "médecin", "hôpital", "médicament", "comprimé", "douleur", "enceinte", "ordonnance",
            "médico", "medicament", "pastilla", "dolor", "embarazad", "receta", "urgencias",
            "ospedale", "farmac", "pastiglia", "dolore", "incinta", "ricetta",
            "remédio", "comprimido", "grávida", "receita",
            "dokter", "ziekenhuis", "medicijn", "zwanger",
            "läkare", "sjukhus", "lege", "sykehus", "læge", "sygehus",
            "lääkär", "sairaala", "lääke",
            "lékař", "lekár", "nemocnic", "léky", "lieky",
            "orvos", "kórház", "gyógyszer",
            "spital", "medicament",
            "liječnik", "lekar", "bolnic", "lijek", "zdravnik",
            "ārst", "slimnīc", "gydytoj", "ligonin",
            "врач", "больниц", "лекарств", "лікар", "лікарн", "болниц", "лекар",
            "γιατρ", "νοσοκομ", "φάρμακ",
            "doktor", "hastane", "ilaç",
        ],
        .law: [
            "police", "lawyer", "court", "arrest", "contract", "passport", "visa", "embassy",
            "polic", "polizei", "politi", "politie", "poliisi", "polis", "rendőr", "poliți", "polícia", "policie", "policij", "policj",
            "adwokat", "prawnik", "umow", "mandat", "sąd",
            "anwalt", "gericht", "vertrag", "strafe",
            "avocat", "tribunal", "contrat", "amende",
            "abogad", "contrato", "multa", "juzgado",
            "avvocat", "contratto",
            "advocaat", "advokat", "asianajaja", "ügyvéd", "odvjetnik", "advokát",
            "полици", "адвокат", "поліці", "αστυνομ", "δικηγόρ", "avukat",
        ],
        .money: [
            "bank", "loan", "mortgage", "debt", "deposit",
            "kredyt", "pożyczk", "dług", "kaucj", "hipotek",
            "kredit", "darlehen", "schulden", "kaution",
            "banque", "prêt", "dette", "caution",
            "banco", "préstamo", "deuda", "fianza", "hipoteca",
            "prestito", "debito", "mutuo",
            "lening", "schuld", "lån", "laina", "úvěr", "hitel",
            "кредит", "долг", "борг", "δάνει", "borç",
        ],
    ]

    /// Everyday words a stem would wrongly catch ("polis", "polic", "policie", "pill").
    static let notTopics: Set<String> = [
        "polish", "polished", "polishing", "policy", "policies", "pillow", "pillows",
    ]

    /// The first topic heard in the text, health first.
    public static func topic(in text: String) -> Topic? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init).filter { !notTopics.contains($0) }
        for topic in [Topic.health, .law, .money] {
            let list = stems[topic] ?? []
            if words.contains(where: { word in list.contains { stem in
                word.hasPrefix(stem)
            } }) { return topic }
        }
        return nil
    }
}

/// One translated turn: what was said, Doddy's line, where it went and the exact facts in either.
public struct TranslatorTurn: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// What was heard before Doddy's line, as transcribed. Nil for the disclosure.
    public let original: String?
    public var text: String
    public let route: TranslatorRoute
    public var facts: [String]

    public init(id: UUID = UUID(), original: String?, text: String, route: TranslatorRoute, facts: [String]) {
        self.id = id
        self.original = original
        self.text = text
        self.route = route
        self.facts = facts
    }
}

/// The translator's state for one conversation. Lives in memory only and is never written to disk.
public struct TranslatorSession: Sendable {
    public private(set) var router: TranslatorRouter
    public private(set) var turns: [TranslatorTurn] = []
    public private(set) var careful: CarefulTopics.Topic?
    public let startedAt: Date
    /// What was heard since Doddy's last line.
    private var heard: [String] = []
    /// The hold-to-talk side held while it was heard, if any.
    public var held: TranslatorDirection?

    /// Messages the app sends to the agent start with this; they are never shown as something said.
    public static let appMessagePrefix = "(app)"

    public init(setup: TranslatorSetup, startedAt: Date) {
        router = TranslatorRouter(setup: setup)
        self.startedAt = startedAt
    }

    public var setup: TranslatorSetup { router.setup }

    /// Something either person said, as transcribed.
    public mutating func heard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(Self.appMessagePrefix) else { return }
        heard.append(trimmed)
        if careful == nil { careful = CarefulTopics.topic(in: trimmed) }
        if !router.isOwnerAside(trimmed, held: held) { _ = router.learnTheirLanguage(from: trimmed) }
    }

    /// One of Doddy's lines. Returns the turn it became.
    @discardableResult
    public mutating func said(_ text: String) -> TranslatorTurn? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let original = heard.isEmpty ? nil : heard.joined(separator: " ")
        heard = []
        let route = router.route(agentLine: trimmed, after: original, held: held)
        held = nil
        if careful == nil { careful = CarefulTopics.topic(in: trimmed) }
        let turn = TranslatorTurn(original: original, text: trimmed, route: route, facts: Self.facts(in: trimmed, original: original, route: route))
        turns.append(turn)
        return turn
    }

    /// The agent corrected a line after an interruption. Facts from what was said are kept.
    public mutating func correct(_ original: String, to corrected: String) {
        guard let index = turns.lastIndex(where: { $0.text == original }) else { return }
        turns[index].text = corrected
        turns[index].facts = Self.facts(in: corrected, original: turns[index].original, route: turns[index].route)
    }

    /// Doddy's line's facts, then those of what it translated, up to the limit.
    private static func facts(in line: String, original: String?, route: TranslatorRoute) -> [String] {
        var facts = ExactFacts.extract(line)
        if case .translation = route, let original {
            for fact in ExactFacts.extract(original) where !facts.contains(fact) { facts.append(fact) }
        }
        return Array(facts.prefix(ExactFacts.limit))
    }

    public func latest(_ direction: TranslatorDirection) -> TranslatorTurn? {
        turns.last { $0.route == .translation(direction) }
    }

    public var latestAside: TranslatorTurn? {
        guard let last = turns.last, last.route == .aside else { return nil }
        return last
    }

    public func summary(endedAt: Date) -> TranslatorSummary {
        TranslatorSummary(
            setup: setup, turnCount: turns.filter { if case .translation = $0.route { true } else { false } }.count,
            duration: max(0, endedAt.timeIntervalSince(startedAt)), endedAt: endedAt,
            transcript: transcript, facts: allFacts)
    }

    /// Plain text for Copy: each line with what it translated.
    var transcript: String {
        turns.map { turn in
            let arrow: String
            switch turn.route {
            case .translation(.toOther): arrow = "→ \(setup.other?.nativeName ?? "them")"
            case .translation(.toOwner): arrow = "→ \(setup.owner.nativeName)"
            case .aside: arrow = "Doddy (only for you)"
            }
            let heard = turn.original.map { "“\($0)”\n" } ?? ""
            return "\(heard)\(arrow): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    var allFacts: [String] {
        var seen = Set<String>()
        return turns.flatMap(\.facts).filter { seen.insert($0).inserted }
    }
}

/// What the end screen offers. The text is kept in memory for five minutes, then dropped (T3).
public struct TranslatorSummary: Equatable, Sendable {
    public static let keepFor: TimeInterval = 5 * 60

    public let setup: TranslatorSetup
    public let turnCount: Int
    public let duration: TimeInterval
    public let endedAt: Date
    public let transcript: String
    public let facts: [String]

    public var expiresAt: Date { endedAt.addingTimeInterval(Self.keepFor) }

    public func isAvailable(at now: Date) -> Bool { now < expiresAt }

    /// "12 turns · Polski ⇄ Español · 6 min".
    public var headline: String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(turnCount) turn\(turnCount == 1 ? "" : "s") · \(setup.pairText) · \(minutes) min"
    }

    /// The note "Save the facts as a note" proposes; nil when nothing exact was said.
    public func factsNote(calendar: Calendar) -> String? {
        guard !facts.isEmpty else { return nil }
        let day = ReminderDueRules.gregorian(calendar).dateComponents([.year, .month, .day], from: endedAt)
        let when = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return "From a translated conversation (\(setup.pairText), \(when)): " + facts.joined(separator: "; ")
    }
}

/// The review sheet for native speakers (`docs/implementation/TRANSLATOR_LANGUAGE_REVIEW.md`),
/// made from `TranslatorLanguages.all` so it can't drift from what ships; a test checks the file.
public enum TranslatorReviewSheet {
    public static func markdown() -> String {
        var out = """
        # Translator lines for native review

        Generated from `TranslatorLanguages.all` (`Packages/DoddyCore/Sources/DoddyCore/Translator.swift`); \
        `TranslatorTests.testReviewSheetMatchesTheCode` fails when they differ. None of these lines has had a \
        native speaker's review yet. For each language, check that the four lines are natural, polite to a \
        stranger, and say the same as the English: Doddy is an AI, on this phone, translating; mistakes are \
        possible; important things should be in writing. Mark a row OK or write the corrected line.

        English reference:
        - AI label: "AI translation · may contain mistakes"
        - Disclosure: "Hi, I'm Doddy, an AI translator on this phone. I'll translate between you two. Please speak normally."
        - Hold to talk: "Hold while you speak"
        - Careful: "AI translation. For anything important, please also get it in writing."

        | Code | Language | AI label | Disclosure (said first) | Hold to talk | Careful | Reviewed |
        |---|---|---|---|---|---|---|

        """
        for language in TranslatorLanguages.all where language.code != "en" {
            let cells = [language.code, language.label, language.aiLabel, language.hello, language.holdToTalk, language.careful, ""]
            out += "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |\n"
        }
        return out
    }
}
