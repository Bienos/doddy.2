import Foundation

// Translator mode (ADR-214 design, ADR-215 build). A mode of Doddy's own conversation (T2), not a
// separate agent: face to face, both ways, or listen only, one way into the owner's language (T1).
// While it is on, the app refuses every tool call, the conversation is private, and nothing of it
// is kept on the iPhone; the owner may copy the text or save the facts as a note on a tap within
// five minutes of the end (T3). Who is talking is told by language, with hold-to-talk as a fallback
// (T4). The quiet word ("Doddy, …" answered on the owner's half, T5) is off since 21 Oct 2026
// (ADR-574): every line is translated, including ones that name Doddy.
// Native voices per language (T6) wait for a listening pass; this build uses Doddy's voice.

public enum TranslatorKind: String, Equatable, Sendable, CaseIterable {
    /// Both ways, the phone between two people; their half of the screen faces them.
    case faceToFace = "face_to_face"
    /// One way into the owner's language: a guide, a talk, an announcement. Doddy speaks only to the owner.
    case listen
}

/// One of the translator's languages: the 37 European ones Doddy speaks (ADR-212) and, since 12 Nov
/// 2026, 52 more, every other language ElevenLabs accepts (decision 2026-11-12-translator-more-languages), with the
/// lines shown or said to the other person in that language. These lines were written for this build
/// and still need a native speaker's review before release (docs/implementation/TRANSLATOR_STATUS.md).
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

    /// Written right to left: their half of the screen is laid out from the right.
    public var isRightToLeft: Bool { Self.rightToLeft.contains(code) }

    private static let rightToLeft: Set<String> = ["ar", "ckb", "fa", "he", "ps", "sd", "ur"]
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
        // Beyond Europe (12 Nov 2026, owner: "Dodaj więcej języków do tłumacza naszego"; decision
        // 2026-11-12-translator-more-languages). Each is in ElevenLabs' Eleven v3 list; the live agent
        // needs a preset for it (docs/OWNER_QUEUE.md). Written without a native speaker's review.
        .init(code: "ar", nativeName: "العربية", englishName: "Arabic",
              aiLabel: "ترجمة بالذكاء الاصطناعي · قد تحتوي على أخطاء",
              hello: "مرحبًا، أنا Doddy، مترجم بالذكاء الاصطناعي على هذا الهاتف. سأترجم بينكما. تحدّثا بشكل طبيعي من فضلكما.",
              holdToTalk: "اضغط مع الاستمرار أثناء التحدث",
              careful: "ترجمة بالذكاء الاصطناعي. في الأمور المهمة، يُرجى الحصول عليها مكتوبةً أيضًا."),
        .init(code: "zh", nativeName: "中文", englishName: "Chinese",
              aiLabel: "AI 翻译 · 可能有误",
              hello: "你好，我是 Doddy，这部手机上的 AI 翻译。我会在你们两位之间翻译。请正常说话。",
              holdToTalk: "说话时请按住",
              careful: "AI 翻译。重要事项请另外以书面形式确认。"),
        .init(code: "ja", nativeName: "日本語", englishName: "Japanese",
              aiLabel: "AI翻訳 · 誤りを含む場合があります",
              hello: "こんにちは、Doddyです。このスマートフォンのAI翻訳です。お二人の会話を通訳します。普段どおりに話してください。",
              holdToTalk: "話している間、押し続けてください",
              careful: "AI翻訳です。大切な内容は、書面でもご確認ください。"),
        .init(code: "ko", nativeName: "한국어", englishName: "Korean",
              aiLabel: "AI 번역 · 오류가 있을 수 있음",
              hello: "안녕하세요, 저는 이 휴대폰의 AI 번역기 Doddy입니다. 두 분 사이에서 통역해 드릴게요. 평소처럼 말씀해 주세요.",
              holdToTalk: "말하는 동안 길게 누르세요",
              careful: "AI 번역입니다. 중요한 내용은 서면으로도 받아 두세요."),
        .init(code: "hi", nativeName: "हिन्दी", englishName: "Hindi",
              aiLabel: "AI अनुवाद · इसमें गलतियाँ हो सकती हैं",
              hello: "नमस्ते, मैं Doddy हूँ, इस फ़ोन पर एक AI अनुवादक। मैं आप दोनों के बीच अनुवाद करूँगा। कृपया सामान्य रूप से बोलें।",
              holdToTalk: "बोलते समय दबाए रखें",
              careful: "AI अनुवाद। किसी भी ज़रूरी बात के लिए, कृपया उसे लिखित में भी लें।"),
        .init(code: "bn", nativeName: "বাংলা", englishName: "Bengali",
              aiLabel: "AI অনুবাদ · ভুল থাকতে পারে",
              hello: "হ্যালো, আমি Doddy, এই ফোনের একটি AI অনুবাদক। আমি আপনাদের দুজনের মধ্যে অনুবাদ করব। দয়া করে স্বাভাবিকভাবে কথা বলুন।",
              holdToTalk: "কথা বলার সময় চেপে ধরে রাখুন",
              careful: "AI অনুবাদ। গুরুত্বপূর্ণ কিছুর জন্য অনুগ্রহ করে লিখিতভাবেও নিয়ে নিন।"),
        .init(code: "ur", nativeName: "اردو", englishName: "Urdu",
              aiLabel: "اے آئی ترجمہ · اس میں غلطیاں ہو سکتی ہیں",
              hello: "ہیلو، میں Doddy ہوں، اس فون پر ایک اے آئی مترجم۔ میں آپ دونوں کے درمیان ترجمہ کروں گا۔ براہِ کرم معمول کے مطابق بات کریں۔",
              holdToTalk: "بولتے وقت دبا کر رکھیں",
              careful: "اے آئی ترجمہ۔ کسی بھی اہم بات کے لیے براہِ کرم اسے تحریری طور پر بھی لیں۔"),
        .init(code: "fa", nativeName: "فارسی", englishName: "Persian",
              aiLabel: "ترجمه با هوش مصنوعی · ممکن است اشتباه داشته باشد",
              hello: "سلام، من Doddy هستم، مترجم هوش مصنوعی روی این گوشی. بین شما دو نفر ترجمه می‌کنم. لطفاً عادی صحبت کنید.",
              holdToTalk: "هنگام صحبت، نگه دارید",
              careful: "ترجمه با هوش مصنوعی. برای موارد مهم، لطفاً آن را کتبی هم بگیرید."),
        .init(code: "he", nativeName: "עברית", englishName: "Hebrew",
              aiLabel: "תרגום AI · עלול להכיל טעויות",
              hello: "שלום, אני Doddy, מתורגמן AI בטלפון הזה. אתרגם ביניכם. דברו כרגיל, בבקשה.",
              holdToTalk: "החזיקו לחוץ בזמן הדיבור",
              careful: "תרגום AI. בכל דבר חשוב, בקשו לקבל אותו גם בכתב."),
        .init(code: "vi", nativeName: "Tiếng Việt", englishName: "Vietnamese",
              aiLabel: "Bản dịch AI · có thể có lỗi",
              hello: "Xin chào, tôi là Doddy, trình phiên dịch AI trên điện thoại này. Tôi sẽ dịch giữa hai người. Xin cứ nói bình thường.",
              holdToTalk: "Nhấn giữ trong khi nói",
              careful: "Bản dịch AI. Với những việc quan trọng, xin hãy yêu cầu thêm bản viết."),
        .init(code: "th", nativeName: "ไทย", englishName: "Thai",
              aiLabel: "แปลโดย AI · อาจมีข้อผิดพลาด",
              hello: "สวัสดีครับ ผมชื่อ Doddy เป็นนักแปล AI ในโทรศัพท์เครื่องนี้ ผมจะแปลระหว่างคุณทั้งสอง กรุณาพูดตามปกติครับ",
              holdToTalk: "กดค้างไว้ขณะพูด",
              careful: "แปลโดย AI สำหรับเรื่องสำคัญ กรุณาขอเป็นลายลักษณ์อักษรด้วย"),
        .init(code: "id", nativeName: "Bahasa Indonesia", englishName: "Indonesian",
              aiLabel: "Terjemahan AI · mungkin ada kesalahan",
              hello: "Halo, saya Doddy, penerjemah AI di ponsel ini. Saya akan menerjemahkan di antara Anda berdua. Silakan bicara seperti biasa.",
              holdToTalk: "Tahan selama Anda berbicara",
              careful: "Terjemahan AI. Untuk hal penting, mohon minta juga secara tertulis."),
        .init(code: "ms", nativeName: "Bahasa Melayu", englishName: "Malay",
              aiLabel: "Terjemahan AI · mungkin terdapat kesilapan",
              hello: "Helo, saya Doddy, penterjemah AI dalam telefon ini. Saya akan menterjemah antara anda berdua. Sila bercakap seperti biasa.",
              holdToTalk: "Tekan dan tahan semasa anda bercakap",
              careful: "Terjemahan AI. Untuk perkara penting, sila dapatkan juga secara bertulis."),
        .init(code: "fil", nativeName: "Filipino", englishName: "Filipino",
              aiLabel: "Pagsasalin ng AI · maaaring may mali",
              hello: "Kumusta, ako si Doddy, isang AI na tagasalin sa teleponong ito. Isasalin ko ang usapan ninyong dalawa. Magsalita lang po kayo nang normal.",
              holdToTalk: "Pindutin nang matagal habang nagsasalita",
              careful: "Pagsasalin ng AI. Para sa mahahalagang bagay, pakihingi rin ito nang nakasulat."),
        .init(code: "sw", nativeName: "Kiswahili", englishName: "Swahili",
              aiLabel: "Tafsiri ya AI · inaweza kuwa na makosa",
              hello: "Habari, mimi ni Doddy, mtafsiri wa AI kwenye simu hii. Nitatafsiri kati yenu wawili. Tafadhali ongeeni kama kawaida.",
              holdToTalk: "Shikilia unapozungumza",
              careful: "Tafsiri ya AI. Kwa jambo lolote muhimu, tafadhali omba pia kwa maandishi."),
        .init(code: "ka", nativeName: "ქართული", englishName: "Georgian",
              aiLabel: "AI თარგმანი · შესაძლოა შეიცავდეს შეცდომებს",
              hello: "გამარჯობა, მე ვარ Doddy, ხელოვნური ინტელექტის თარჯიმანი ამ ტელეფონზე. თქვენ ორს შორის ვთარგმნი. გთხოვთ, ჩვეულებრივად ისაუბროთ.",
              holdToTalk: "საუბრისას ხანგრძლივად დააჭირეთ",
              careful: "AI თარგმანი. მნიშვნელოვანი საკითხებისთვის, გთხოვთ, ის წერილობითაც მოითხოვოთ."),
        // Every other language on ElevenLabs' Eleven v3 list that it accepts as an agent language (12 Nov 2026,
        // owner: "i tak chce więcej języków"). Codes as ElevenLabs writes them: "ast" and "yue" have three letters.
        .init(code: "af", nativeName: "Afrikaans", englishName: "Afrikaans",
              aiLabel: "KI-vertaling · kan foute bevat",
              hello: "Hallo, ek is Doddy, 'n KI-vertaler op hierdie foon. Ek sal tussen julle twee vertaal. Praat asseblief normaal.",
              holdToTalk: "Hou in terwyl jy praat",
              careful: "KI-vertaling. Vra asseblief vir enigiets belangriks ook op skrif."),
        .init(code: "hy", nativeName: "Հայերեն", englishName: "Armenian",
              aiLabel: "ԱԲ թարգմանություն · կարող է սխալներ պարունակել",
              hello: "Բարև, ես Doddy-ն եմ՝ արհեստական բանականությամբ թարգմանիչ այս հեռախոսում։ Ես կթարգմանեմ ձեր երկուսի միջև։ Խնդրում եմ, խոսեք սովորականի պես։",
              holdToTalk: "Սեղմած պահեք, երբ խոսում եք",
              careful: "ԱԲ թարգմանություն։ Կարևոր հարցերի համար խնդրում ենք ստանալ նաև գրավոր։"),
        .init(code: "as", nativeName: "অসমীয়া", englishName: "Assamese",
              aiLabel: "AI অনুবাদ · ভুল থাকিব পাৰে",
              hello: "নমস্কাৰ, মই Doddy, এই ফোনটোৰ এজন AI অনুবাদক। মই আপোনালোক দুজনৰ মাজত অনুবাদ কৰিম। অনুগ্ৰহ কৰি স্বাভাৱিকভাৱে কথা কওক।",
              holdToTalk: "কথা কোৱাৰ সময়ত টিপি ধৰি ৰাখক",
              careful: "AI অনুবাদ। গুৰুত্বপূৰ্ণ কথাৰ বাবে অনুগ্ৰহ কৰি লিখিতভাৱেও লওক।"),
        .init(code: "ast", nativeName: "Asturianu", englishName: "Asturian",
              aiLabel: "Traducción con IA · pue tener errores",
              hello: "Hola, soi Doddy, un traductor d'IA nesti teléfonu. Voi traducir ente vosotros dos. Falái con normalidá.",
              holdToTalk: "Caltién primío mientres fales",
              careful: "Traducción con IA. Pa coses importantes, pidi que te lo den tamién per escrito."),
        .init(code: "az", nativeName: "Azərbaycanca", englishName: "Azerbaijani",
              aiLabel: "Süni intellekt tərcüməsi · səhvlər ola bilər",
              hello: "Salam, mən Doddy, bu telefondakı süni intellekt tərcüməçisiyəm. Sizin ikiniz arasında tərcümə edəcəyəm. Zəhmət olmasa, adi qaydada danışın.",
              holdToTalk: "Danışarkən basılı saxlayın",
              careful: "Süni intellekt tərcüməsi. Vacib məsələlər üçün, zəhmət olmasa, bunu yazılı şəkildə də alın."),
        .init(code: "my", nativeName: "မြန်မာ", englishName: "Burmese",
              aiLabel: "AI ဘာသာပြန် · အမှားများ ပါနိုင်သည်",
              hello: "မင်္ဂလာပါ၊ ကျွန်တော်က Doddy ပါ၊ ဒီဖုန်းထဲက AI ဘာသာပြန်ပါ။ ခင်ဗျားတို့ နှစ်ယောက်ကြား ဘာသာပြန်ပေးပါမယ်။ ပုံမှန်အတိုင်း ပြောပါ။",
              holdToTalk: "ပြောနေစဉ် ဖိထားပါ",
              careful: "AI ဘာသာပြန်ဖြစ်ပါသည်။ အရေးကြီးသောကိစ္စများအတွက် စာဖြင့်လည်း ရယူပါ။"),
        .init(code: "yue", nativeName: "粵語", englishName: "Cantonese",
              aiLabel: "AI 翻譯 · 可能有錯",
              hello: "你好，我係 Doddy，呢部手機入面嘅 AI 翻譯。我會幫你哋兩位翻譯。請正常講嘢。",
              holdToTalk: "講嘢嗰陣請㩒住",
              careful: "AI 翻譯。重要嘅事，請另外攞埋書面文件。"),
        .init(code: "gu", nativeName: "ગુજરાતી", englishName: "Gujarati",
              aiLabel: "AI અનુવાદ · તેમાં ભૂલો હોઈ શકે છે",
              hello: "નમસ્તે, હું Doddy છું, આ ફોન પરનો AI અનુવાદક. હું તમારા બંને વચ્ચે અનુવાદ કરીશ. કૃપા કરીને સામાન્ય રીતે બોલો.",
              holdToTalk: "બોલતી વખતે દબાવી રાખો",
              careful: "AI અનુવાદ. કોઈપણ મહત્વની બાબત માટે, કૃપા કરીને તે લેખિતમાં પણ મેળવો."),
        .init(code: "ha", nativeName: "Hausa", englishName: "Hausa",
              aiLabel: "Fassarar AI · tana iya samun kurakurai",
              hello: "Sannu, ni ne Doddy, mai fassara na AI a wannan wayar. Zan fassara tsakaninku biyu. Don Allah ku yi magana kamar yadda kuka saba.",
              holdToTalk: "Riƙe yayin da kake magana",
              careful: "Fassarar AI. Don wani abu mai muhimmanci, don Allah a nemi a rubuta shi ma."),
        .init(code: "jv", nativeName: "Basa Jawa", englishName: "Javanese",
              aiLabel: "Terjemahan AI · bisa ana kaluputan",
              hello: "Halo, aku Doddy, penerjemah AI ing hape iki. Aku bakal nerjemahake ing antarane panjenengan sakloron. Mangga ngomong kaya biasane.",
              holdToTalk: "Pencet terus nalika ngomong",
              careful: "Terjemahan AI. Kanggo bab sing penting, mangga njaluk uga kanthi tulisan."),
        .init(code: "kn", nativeName: "ಕನ್ನಡ", englishName: "Kannada",
              aiLabel: "AI ಅನುವಾದ · ತಪ್ಪುಗಳಿರಬಹುದು",
              hello: "ನಮಸ್ಕಾರ, ನಾನು Doddy, ಈ ಫೋನ್‌ನಲ್ಲಿರುವ AI ಅನುವಾದಕ. ನಾನು ನಿಮ್ಮಿಬ್ಬರ ನಡುವೆ ಅನುವಾದಿಸುತ್ತೇನೆ. ದಯವಿಟ್ಟು ಸಹಜವಾಗಿ ಮಾತನಾಡಿ.",
              holdToTalk: "ಮಾತನಾಡುವಾಗ ಒತ್ತಿ ಹಿಡಿಯಿರಿ",
              careful: "AI ಅನುವಾದ. ಯಾವುದೇ ಮುಖ್ಯ ವಿಷಯಕ್ಕೆ, ದಯವಿಟ್ಟು ಅದನ್ನು ಲಿಖಿತವಾಗಿಯೂ ಪಡೆಯಿರಿ."),
        .init(code: "kk", nativeName: "Қазақша", englishName: "Kazakh",
              aiLabel: "ЖИ аудармасы · қателер болуы мүмкін",
              hello: "Сәлеметсіз бе, мен Doddy, осы телефондағы жасанды интеллект аудармашысымын. Сіздердің екеуіңіздің араңызда аударма жасаймын. Әдеттегідей сөйлей беріңіз.",
              holdToTalk: "Сөйлеген кезде басып тұрыңыз",
              careful: "ЖИ аудармасы. Маңызды мәселелер бойынша оны жазбаша түрде де алыңыз."),
        .init(code: "ky", nativeName: "Кыргызча", englishName: "Kyrgyz",
              aiLabel: "ЖИ котормосу · катачылыктар болушу мүмкүн",
              hello: "Саламатсызбы, мен Doddy, ушул телефондогу жасалма интеллект котормочусумун. Силер экөөңөрдүн ортоңордо которуп берем. Кадимкидей сүйлөй бериңиз.",
              holdToTalk: "Сүйлөп жатканда басып туруңуз",
              careful: "ЖИ котормосу. Маанилүү маселелер боюнча, сураныч, аны жазуу түрүндө да алыңыз."),
        .init(code: "ml", nativeName: "മലയാളം", englishName: "Malayalam",
              aiLabel: "AI വിവർത്തനം · തെറ്റുകൾ ഉണ്ടാകാം",
              hello: "നമസ്കാരം, ഞാൻ Doddy, ഈ ഫോണിലെ ഒരു AI വിവർത്തകൻ. നിങ്ങൾ രണ്ടുപേർക്കുമിടയിൽ ഞാൻ വിവർത്തനം ചെയ്യും. ദയവായി സാധാരണപോലെ സംസാരിക്കൂ.",
              holdToTalk: "സംസാരിക്കുമ്പോൾ അമർത്തിപ്പിടിക്കുക",
              careful: "AI വിവർത്തനം. പ്രധാനപ്പെട്ട കാര്യങ്ങൾക്ക്, ദയവായി അത് എഴുതിയും വാങ്ങുക."),
        .init(code: "mi", nativeName: "Te Reo Māori", englishName: "Māori",
              aiLabel: "Whakamāori AI · tērā pea he hapa kei roto",
              hello: "Kia ora, ko Doddy ahau, he kaiwhakamāori AI i tēnei waea. Ka whakamāori ahau i waenganui i a kōrua. Kōrero noa mai.",
              holdToTalk: "Pēhia roatia i a koe e kōrero ana",
              careful: "Whakamāori AI. Mō ngā take nui, tonoa kia tuhia hoki."),
        .init(code: "mr", nativeName: "मराठी", englishName: "Marathi",
              aiLabel: "AI भाषांतर · यात चुका असू शकतात",
              hello: "नमस्कार, मी Doddy आहे, या फोनवरील AI भाषांतरकार. मी तुम्हा दोघांमध्ये भाषांतर करेन. कृपया नेहमीसारखे बोला.",
              holdToTalk: "बोलताना दाबून ठेवा",
              careful: "AI भाषांतर. कोणत्याही महत्त्वाच्या गोष्टीसाठी, कृपया ती लेखी स्वरूपातही घ्या."),
        .init(code: "mn", nativeName: "Монгол", englishName: "Mongolian",
              aiLabel: "Хиймэл оюуны орчуулга · алдаа гарч болзошгүй",
              hello: "Сайн байна уу, би Doddy, энэ утсан дээрх хиймэл оюун ухаант орчуулагч. Би та хоёрын хооронд орчуулна. Энгийнээр ярина уу.",
              holdToTalk: "Ярьж байхдаа дарж барина уу",
              careful: "Хиймэл оюуны орчуулга. Чухал зүйлийн хувьд үүнийг бичгээр бас авна уу."),
        .init(code: "ne", nativeName: "नेपाली", englishName: "Nepali",
              aiLabel: "AI अनुवाद · गल्ती हुन सक्छ",
              hello: "नमस्ते, म Doddy हुँ, यो फोनमा रहेको AI अनुवादक। म तपाईं दुई जनाको बीचमा अनुवाद गर्नेछु। कृपया सामान्य रूपमा बोल्नुहोस्।",
              holdToTalk: "बोल्दा थिचिराख्नुहोस्",
              careful: "AI अनुवाद। कुनै पनि महत्त्वपूर्ण कुराको लागि, कृपया लिखित रूपमा पनि लिनुहोस्।"),
        .init(code: "oc", nativeName: "Occitan", englishName: "Occitan",
              aiLabel: "Traduccion per IA · pòt conténer d'errors",
              hello: "Adieu, soi Doddy, un traductor d'IA sus aqueste telefòn. Vau traduire entre vosautres dos. Parlatz normalament.",
              holdToTalk: "Tenètz quichat mentre que parlatz",
              careful: "Traduccion per IA. Per quicòm d'important, demandatz-o tanben per escrich."),
        .init(code: "or", nativeName: "ଓଡ଼ିଆ", englishName: "Odia",
              aiLabel: "AI ଅନୁବାଦ · ଭୁଲ ରହିପାରେ",
              hello: "ନମସ୍କାର, ମୁଁ Doddy, ଏହି ଫୋନରେ ଥିବା ଜଣେ AI ଅନୁବାଦକ। ମୁଁ ଆପଣ ଦୁହିଁଙ୍କ ମଧ୍ୟରେ ଅନୁବାଦ କରିବି। ଦୟାକରି ସାଧାରଣ ଭାବରେ କଥା ହୁଅନ୍ତୁ।",
              holdToTalk: "କଥା କହିବା ସମୟରେ ଦବାଇ ରଖନ୍ତୁ",
              careful: "AI ଅନୁବାଦ। ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ ବିଷୟ ପାଇଁ, ଦୟାକରି ଏହାକୁ ଲିଖିତ ଭାବରେ ମଧ୍ୟ ନିଅନ୍ତୁ।"),
        .init(code: "ps", nativeName: "پښتو", englishName: "Pashto",
              aiLabel: "د مصنوعي ځیرکتیا ژباړه · ښایي تېروتنې ولري",
              hello: "سلام، زه Doddy یم، په دې تلیفون کې د مصنوعي ځیرکتیا ژباړونکی. زه به ستاسو دواړو ترمنځ ژباړه وکړم. مهرباني وکړئ په عادي ډول خبرې وکړئ.",
              holdToTalk: "د خبرو پر مهال یې ټینګ ونیسئ",
              careful: "د مصنوعي ځیرکتیا ژباړه. د مهمو مسایلو لپاره، مهرباني وکړئ دا په لیکلي ډول هم واخلئ."),
        .init(code: "pa", nativeName: "ਪੰਜਾਬੀ", englishName: "Punjabi",
              aiLabel: "AI ਅਨੁਵਾਦ · ਇਸ ਵਿੱਚ ਗਲਤੀਆਂ ਹੋ ਸਕਦੀਆਂ ਹਨ",
              hello: "ਸਤ ਸ੍ਰੀ ਅਕਾਲ, ਮੈਂ Doddy ਹਾਂ, ਇਸ ਫ਼ੋਨ 'ਤੇ ਇੱਕ AI ਅਨੁਵਾਦਕ। ਮੈਂ ਤੁਹਾਡੇ ਦੋਵਾਂ ਵਿਚਕਾਰ ਅਨੁਵਾਦ ਕਰਾਂਗਾ। ਕਿਰਪਾ ਕਰਕੇ ਆਮ ਵਾਂਗ ਬੋਲੋ।",
              holdToTalk: "ਬੋਲਦੇ ਸਮੇਂ ਦਬਾ ਕੇ ਰੱਖੋ",
              careful: "AI ਅਨੁਵਾਦ। ਕਿਸੇ ਵੀ ਜ਼ਰੂਰੀ ਗੱਲ ਲਈ, ਕਿਰਪਾ ਕਰਕੇ ਇਸ ਨੂੰ ਲਿਖਤੀ ਰੂਪ ਵਿੱਚ ਵੀ ਲਓ।"),
        .init(code: "sd", nativeName: "سنڌي", englishName: "Sindhi",
              aiLabel: "AI ترجمو · ان ۾ غلطيون ٿي سگهن ٿيون",
              hello: "هيلو، مان Doddy آهيان، هن فون تي هڪ AI ترجمان. مان توهان ٻنهي جي وچ ۾ ترجمو ڪندس. مهرباني ڪري عام طرح ڳالهايو.",
              holdToTalk: "ڳالهائڻ وقت دٻائي رکو",
              careful: "AI ترجمو. ڪنهن به اهم ڳالهه لاءِ، مهرباني ڪري ان کي لکت ۾ به وٺو."),
        .init(code: "so", nativeName: "Soomaali", englishName: "Somali",
              aiLabel: "Turjumaad AI · waxaa laga yaabaa inay khaldan tahay",
              hello: "Salaan, waxaan ahay Doddy, turjumaan AI ah oo ku jira taleefankan. Waxaan idinka dhex turjumi doonaa labadiinna. Fadlan si caadi ah u hadla.",
              holdToTalk: "Riix oo hay inta aad hadlayso",
              careful: "Turjumaad AI. Wax kasta oo muhiim ah, fadlan sidoo kale qoraal ahaan u qaado."),
        .init(code: "tg", nativeName: "Тоҷикӣ", englishName: "Tajik",
              aiLabel: "Тарҷумаи зеҳни сунъӣ · метавонад хато дошта бошад",
              hello: "Салом, ман Doddy ҳастам, тарҷумони зеҳни сунъӣ дар ин телефон. Ман байни шумо ду нафар тарҷума мекунам. Лутфан муқаррарӣ гап занед.",
              holdToTalk: "Ҳангоми гап задан пахш карда нигоҳ доред",
              careful: "Тарҷумаи зеҳни сунъӣ. Барои масъалаҳои муҳим, лутфан онро хаттӣ ҳам гиред."),
        .init(code: "ta", nativeName: "தமிழ்", englishName: "Tamil",
              aiLabel: "AI மொழிபெயர்ப்பு · பிழைகள் இருக்கலாம்",
              hello: "வணக்கம், நான் Doddy, இந்த போனில் உள்ள AI மொழிபெயர்ப்பாளர். உங்கள் இருவருக்கும் இடையே நான் மொழிபெயர்ப்பேன். தயவுசெய்து இயல்பாகப் பேசுங்கள்.",
              holdToTalk: "பேசும்போது அழுத்திப் பிடிக்கவும்",
              careful: "AI மொழிபெயர்ப்பு. முக்கியமான எதற்கும், தயவுசெய்து அதை எழுத்து மூலமாகவும் பெறுங்கள்."),
        .init(code: "te", nativeName: "తెలుగు", englishName: "Telugu",
              aiLabel: "AI అనువాదం · తప్పులు ఉండవచ్చు",
              hello: "నమస్కారం, నేను Doddy, ఈ ఫోన్‌లోని AI అనువాదకుడిని. మీ ఇద్దరి మధ్య నేను అనువదిస్తాను. దయచేసి మామూలుగా మాట్లాడండి.",
              holdToTalk: "మాట్లాడేటప్పుడు నొక్కి పట్టుకోండి",
              careful: "AI అనువాదం. ముఖ్యమైన విషయాల కోసం, దయచేసి దాన్ని రాతపూర్వకంగా కూడా తీసుకోండి."),
        .init(code: "uz", nativeName: "Oʻzbekcha", englishName: "Uzbek",
              aiLabel: "Sunʼiy intellekt tarjimasi · xatolar boʻlishi mumkin",
              hello: "Salom, men Doddy, ushbu telefondagi sunʼiy intellekt tarjimoniman. Sizlar ikkingiz oʻrtasida tarjima qilaman. Iltimos, odatdagidek gapiring.",
              holdToTalk: "Gapirayotganda bosib turing",
              careful: "Sunʼiy intellekt tarjimasi. Muhim masalalar uchun, iltimos, uni yozma ravishda ham oling."),
        .init(code: "yo", nativeName: "Yorùbá", englishName: "Yoruba",
              aiLabel: "Ìtumọ̀ AI · ó lè ní àṣìṣe",
              hello: "Ẹ n lẹ́, èmi ni Doddy, olùtúmọ̀ AI lórí fóònù yìí. Màá ṣe ìtumọ̀ láàrin ẹ̀yin méjèèjì. Ẹ jọ̀ọ́, ẹ sọ̀rọ̀ bí ẹ ṣe máa ń sọ.",
              holdToTalk: "Tẹ̀ ẹ́ mọ́lẹ̀ nígbà tí o bá ń sọ̀rọ̀",
              careful: "Ìtumọ̀ AI. Fún ohunkóhun tó ṣe pàtàkì, ẹ jọ̀ọ́ ẹ gbà á ní ìwé pẹ̀lú."),
        // Seven more ElevenLabs accepts as agent languages (its own list, read from a refusal on 12 Nov 2026);
        // it refused Lingala, Cebuano and Chichewa, so they are not here.
        .init(code: "am", nativeName: "አማርኛ", englishName: "Amharic",
              aiLabel: "የAI ትርጉም · ስህተቶች ሊኖሩት ይችላሉ",
              hello: "ሰላም፣ እኔ Doddy ነኝ፣ በዚህ ስልክ ላይ ያለ የAI ተርጓሚ። በሁለታችሁ መካከል እተረጉማለሁ። እባክዎ እንደተለመደው ይናገሩ።",
              holdToTalk: "በሚናገሩበት ጊዜ ተጭነው ይያዙ",
              careful: "የAI ትርጉም። ለማንኛውም አስፈላጊ ጉዳይ፣ እባክዎ በጽሑፍም ይቀበሉት።"),
        .init(code: "lo", nativeName: "ລາວ", englishName: "Lao",
              aiLabel: "ການແປໂດຍ AI · ອາດມີຂໍ້ຜິດພາດ",
              hello: "ສະບາຍດີ, ຂ້ອຍແມ່ນ Doddy, ນັກແປ AI ໃນໂທລະສັບນີ້. ຂ້ອຍຈະແປລະຫວ່າງທ່ານທັງສອງ. ກະລຸນາເວົ້າຕາມປົກກະຕິ.",
              holdToTalk: "ກົດຄ້າງໄວ້ໃນຂະນະທີ່ເວົ້າ",
              careful: "ການແປໂດຍ AI. ສຳລັບເລື່ອງສຳຄັນ, ກະລຸນາຂໍເປັນລາຍລັກອັກສອນນຳ."),
        .init(code: "lg", nativeName: "Luganda", englishName: "Luganda",
              aiLabel: "Okuvvuunula kwa AI · kuyinza okubaamu ensobi",
              hello: "Gyebale ko, nze Doddy, omuvvuunuzi wa AI ku ssimu eno. Nja kuvvuunula wakati wammwe ababiri. Mwogere nga bwe mwogera bulijjo.",
              holdToTalk: "Kwata nga oyogera",
              careful: "Okuvvuunula kwa AI. Ku nsonga enkulu, musabe era bibawandiikirwe."),
        .init(code: "sn", nativeName: "chiShona", englishName: "Shona",
              aiLabel: "Shanduro yeAI · inogona kuva nezvikanganiso",
              hello: "Mhoro, ndini Doddy, muturikiri weAI parunhare urwu. Ndichashandura pakati penyu mese vaviri. Ndapota taurai sezvamunogara muchiita.",
              holdToTalk: "Dzvanya ubate paunenge uchitaura",
              careful: "Shanduro yeAI. Pazvinhu zvakakosha, ndapota kumbirai zvinyorwe zvakare."),
        .init(code: "ckb", nativeName: "کوردی", englishName: "Central Kurdish",
              aiLabel: "وەرگێڕانی AI · لەوانەیە هەڵەی تێدا بێت",
              hello: "سڵاو، من Doddyم، وەرگێڕێکی AI لەسەر ئەم مۆبایلە. لە نێوان ئێوەی دوو کەس وەرگێڕان دەکەم. تکایە بە شێوەی ئاسایی قسە بکەن.",
              holdToTalk: "لە کاتی قسەکردندا دایگرە",
              careful: "وەرگێڕانی AI. بۆ هەر شتێکی گرنگ، تکایە بە نووسینیش وەریبگرن."),
        .init(code: "wo", nativeName: "Wolof", englishName: "Wolof",
              aiLabel: "Firi AI · man na am ay njuumte",
              hello: "Salaam aleekum, maa ngi tudd Doddy, tekkikat AI ci telefon bii. Dinaa tekki ci seen diggante ñoom ñaar. Waxleen ni ngeen di wax.",
              holdToTalk: "Bësal te téye ba ngay wax",
              careful: "Firi AI. Ngir lu am solo, baaleen ñu bind leen ko itam."),
        .init(code: "zu", nativeName: "isiZulu", englishName: "Zulu",
              aiLabel: "Ukuhumusha kwe-AI · kungase kube namaphutha",
              hello: "Sawubona, nginguDoddy, umhumushi we-AI kulolu cingo. Ngizohumusha phakathi kwenu nobabili. Sicela nikhulume njengokujwayelekile.",
              holdToTalk: "Bamba ngenkathi ukhuluma",
              careful: "Ukuhumusha kwe-AI. Kunoma yini ebalulekile, sicela uyithole nangokubhaliwe."),
    ]

    /// How many languages the translator speaks: 89 since 12 Nov 2026, the 37 European ones of ADR-212 and
    /// every other language ElevenLabs accepts as an agent language (not Basque, Albanian, Lingala, Cebuano or Chichewa).
    public static var count: Int { all.count }

    private static let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// Older or other codes for the same language: "nb"/"nn" Norwegian, "iw" Hebrew, "in" Indonesian,
    /// "tl" Tagalog as Filipino, "cmn" Mandarin as Chinese.
    private static let aliases = ["nb": "no", "nn": "no", "iw": "he", "in": "id", "tl": "fil", "cmn": "zh"]

    /// A language code (two letters, or ElevenLabs' three for Filipino, Asturian, Cantonese and Central Kurdish),
    /// case-insensitive. Nil when Doddy doesn't speak it.
    public static func named(_ code: String) -> TranslatorLanguage? {
        let key = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return byCode[aliases[key] ?? key]
    }

    public static var english: TranslatorLanguage { byCode["en"]! }

    /// The owner's language when they didn't say: the starting language from Settings, else the
    /// iPhone's language, else English.
    public static func ownerDefault(settingCode: String?, deviceCode: String?) -> TranslatorLanguage {
        settingCode.flatMap(named) ?? deviceCode.flatMap(named) ?? english
    }

    /// What Home › Translate shows before the owner picks (ADR-574): the two languages used last
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
        let theirs = other.map { "\($0.englishName) (\($0.code))" }
            ?? "not known yet: the first language you hear that isn't \(owner.englishName) is theirs"
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
        // 9 Nov 2026 (owner: "słyszy obcego i od razu tłumaczy na polski"): the conversation log showed
        // Doddy calling start_translator again, being refused and talking about it in English instead of
        // translating. Then (owner: "niech nic nie mówi, zmień zasady"): Doddy says nothing of his own,
        // no greeting, no spoken disclosure, no question; their half of the screen shows the AI label.
        // 12 Nov 2026, live test conversations (decision 2026-11-12-translator-more-languages): asked
        // "where is the nearest pharmacy?", the agent called find_places and answered instead of translating,
        // and said a Thai reply again in Thai. The interpreter rule now comes first, with that example.
        var text = preset.interpreterOnly + " Translator mode is on from the start: \(preset.agentDescription)"
        text += " It is already on: never call start_translator, and never talk about the mode. " + silentStart
        text += " From the first word, " + preset.directions
        text += " " + preset.nothingIsForYou
        return text
    }

    /// The owner's rule of 9 Nov 2026, said where it replaces the prompt's older lines.
    static let silentStart = "Say nothing of your own: no greeting, no AI translator disclosure, no question about what to translate (this replaces those lines below; the other person's half of the screen shows, in their language, that this is an AI translation). Wait in silence until someone speaks."

    /// What Doddy says first in a conversation opened for translating (`{{opening_line}}`): nothing
    /// (owner, 9 Nov 2026: "niech nic nie mówi"). An empty first message makes the agent wait for
    /// someone to speak.
    public static func openingLine(_ setup: TranslatorSetup) -> String { "" }
}

extension TranslatorSetup {
    /// Said first: nothing is for Doddy, with the example the live agent got wrong (12 Nov 2026).
    var interpreterOnly: String {
        switch kind {
        case .faceToFace:
            let theirs = other?.englishName ?? "the other person's language"
            return "YOU ARE ONLY AN INTERPRETER NOW. Everything you hear is said to the other person, never to you. When the user asks \"where is the nearest pharmacy?\", you say that same question in \(theirs) and nothing else: you don't look it up, don't call any tool, don't say you are checking, don't answer."
        case .listen:
            return "YOU ARE ONLY AN INTERPRETER NOW. Nothing you hear is said to you: you translate it into \(owner.englishName) for the user, and never answer it, look anything up or call a tool."
        }
    }

    /// Questions and requests are translated, never acted on; nothing is said again in its own language;
    /// after a refused tool, the line is translated at once.
    var nothingIsForYou: String {
        let owner = self.owner.englishName
        switch kind {
        case .listen:
            return "Never say a line again in the language it was said in: everything becomes \(owner). If you called a tool anyway and the app refused it, translate what was said into \(owner) at once and say nothing else."
        case .faceToFace:
            let theirs = other?.englishName ?? "their language"
            return "Nothing anyone says is meant for you: a question or a request (\"where is…\", \"can you…\", \"call…\") is translated for the other person, never answered or acted on, and you call no tool (the app refuses them all). Never say a line again in the language it was said in: \(theirs) always becomes \(owner), \(owner) always becomes \(theirs). If you called a tool anyway and the app refused it, what was said was for the other person: translate it at once (\(owner) into \(theirs), \(theirs) into \(owner)) and say nothing else."
        }
    }

    /// Which way each line goes, said plainly for the agent. With their language unknown, the user's
    /// own first words go into English (or Polish for an English speaker) until the other person speaks.
    var directions: String {
        let owner = self.owner.englishName
        switch (kind, other) {
        case (.listen, _):
            return "translate everything you hear into \(owner) for the user, one short line at a time, as soon as each sentence ends. Say nothing else."
        case (.faceToFace, let other?):
            return "translate every turn as soon as it ends: \(owner) into \(other.englishName), \(other.englishName) into \(owner). Say only the translation."
        case (.faceToFace, nil):
            let fallback = self.owner == TranslatorLanguages.english ? TranslatorLanguages.named("pl")! : TranslatorLanguages.english
            return "translate every turn as soon as it ends. When the other person speaks, translate what they said into \(owner). When the user speaks \(owner), translate it into the other person's language; until you have heard it, into \(fallback.englishName). Say only the translation."
        }
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
                return .invalid(name: name, reason: "their_language must be one of Doddy's \(TranslatorLanguages.count) language codes, or detect")
            }
            theirs = language
        }
        var yours: TranslatorLanguage?
        if let yourRaw = args.text("your_language") {
            guard let language = TranslatorLanguages.named(yourRaw) else {
                return .invalid(name: name, reason: "your_language must be one of Doddy's \(TranslatorLanguages.count) language codes")
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
    /// stop_translator, and start_translator, which is answered "already on" (`translatorAlreadyOn`)
    /// so the agent keeps translating instead of explaining a refusal.
    public static func allows(_ request: VoiceToolRequest) -> Bool {
        switch request {
        case .stopTranslator, .startTranslator: return true
        default: return false
        }
    }
}

extension VoiceToolReply {
    /// The user tapped Start. The agent switches into the mode and says the disclosure first.
    public static func translatorStarted(_ setup: TranslatorSetup) -> String {
        var lines = ["started: translator mode is on, \(setup.agentDescription) From now on follow the Translator mode rules: translate, never answer; the app runs no tools until it ends."]
        switch (setup.kind, setup.other) {
        case (.faceToFace, _):
            // Owner, 9 Nov 2026: no spoken disclosure and no "what should I translate?" (replaces ADR-619 here).
            lines.append(TranslatorPrompt.silentStart + " Then " + setup.directions)
            lines.append(setup.nothingIsForYou)
        case (.listen, _):
            lines.append("Say nothing to anyone else. Translate each thing you hear into \(setup.owner.englishName) for the user, one short line at a time.")
            lines.append(setup.nothingIsForYou)
        }
        return lines.joined(separator: " ")
    }

    /// start_translator while the mode is on: nothing changes, and the agent goes on translating.
    public static func translatorAlreadyOn(_ setup: TranslatorSetup) -> String {
        "started: translator mode is already on, \(setup.agentDescription) Nothing changed. Don't mention it and don't call start_translator again; "
            + setup.directions + " " + setup.nothingIsForYou
    }

    public static let translatorDeclined = "declined: the user chose not to start translating. Nothing changed; talk normally."
    public static let translatorStopped = "stopped: translator mode is off. Nothing from it is kept on the iPhone. Talk with the user normally again; tools work again."
    public static let translatorNotOn = "stopped: translator mode wasn't on. Nothing changed."

    /// Any tool asked for while translating. The tool's name is the agent's own text, so it
    /// follows as data (ToolData).
    /// 12 Nov 2026: after the old "Keep translating", the live agent asked the user which town they meant
    /// instead of translating their question; this wording got the translation said in the live checks.
    public static func translatorRefused(_ name: String) -> String {
        "refused: translator mode is on, so the app doesn't run the tool below or any other tool. Nothing was looked up, saved or changed. What was just said was meant for the other person, not for you: translate it now into the other language and say nothing else. Don't answer it and don't ask about it.\n"
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
        if script != .unknown, script != profile.script, !profile.also.contains(script) { return 0 }
        var points = script == profile.script && script != .latin ? 3 : 0
        points += lower.unicodeScalars.filter { profile.letters.unicodeScalars.contains($0) }.count
        let words = lower.split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
        points += 2 * words.filter { profile.words.contains($0) }.count
        return points
    }

    enum Script: Hashable {
        case latin, cyrillic, greek, arabic, hebrew, devanagari, bengali, thai, georgian, hangul, kana, han
        case armenian, myanmar, gurmukhi, gujarati, odia, tamil, telugu, kannada, malayalam, ethiopic, lao, unknown
        /// On a tie the first wins, Latin last (as before 12 Nov 2026: Cyrillic, then Greek, then Latin).
        private static let order: [Script] = [.cyrillic, .greek, .arabic, .hebrew, .devanagari, .bengali, .thai, .georgian, .hangul, .kana, .han,
                                              .armenian, .myanmar, .gurmukhi, .gujarati, .odia, .tamil, .telugu, .kannada, .malayalam,
                                              .ethiopic, .lao, .latin]

        static func of(_ text: String) -> Script {
            var counts: [Script: Int] = [:]
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                if let script = script(of: scalar.value) { counts[script, default: 0] += 1 }
            }
            let top = counts.values.max() ?? 0
            if top == 0 { return .unknown }
            // Japanese writes kanji between its kana; Chinese never uses kana.
            if let kana = counts[.kana], kana + (counts[.han] ?? 0) >= top { return .kana }
            return order.first { counts[$0] == top } ?? .unknown
        }

        private static func script(of value: UInt32) -> Script? {
            switch value {
            case 0x0400...0x04FF: .cyrillic
            case 0x0370...0x03FF, 0x1F00...0x1FFF: .greek
            // Latin Extended Additional holds Vietnamese letters such as ạ, ế and ự.
            case 0x0041...0x024F, 0x1E00...0x1EFF: .latin
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: .arabic
            case 0x0590...0x05FF, 0xFB1D...0xFB4F: .hebrew
            case 0x0900...0x097F: .devanagari
            case 0x0980...0x09FF: .bengali
            case 0x0E00...0x0E7F: .thai
            case 0x10A0...0x10FF, 0x1C90...0x1CBF, 0x2D00...0x2D2F: .georgian
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: .hangul
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: .kana
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: .han
            case 0x0530...0x058F, 0xFB13...0xFB17: .armenian
            case 0x1000...0x109F: .myanmar
            case 0x0A00...0x0A7F: .gurmukhi
            case 0x0A80...0x0AFF: .gujarati
            case 0x0B00...0x0B7F: .odia
            case 0x0B80...0x0BFF: .tamil
            case 0x0C00...0x0C7F: .telugu
            case 0x0C80...0x0CFF: .kannada
            case 0x0D00...0x0D7F: .malayalam
            case 0x1200...0x139F, 0x2D80...0x2DDF: .ethiopic
            case 0x0E80...0x0EFF: .lao
            default: nil
            }
        }
    }

    struct Profile {
        let script: Script
        /// Other scripts the language is also written in: Serbian in Cyrillic, Japanese in kanji alone.
        let also: Set<Script>
        /// Letters that point to this language among the others in its script.
        let letters: String
        let words: Set<String>

        init(script: Script, also: Set<Script> = [], letters: String, words: Set<String>) {
            self.script = script
            self.also = also
            self.letters = letters
            self.words = words
        }
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
        "sr": .init(script: .latin, also: [.cyrillic], letters: "čćđšžђћјљњџ", words: ["je", "i", "se", "na", "da", "šta", "gde", "koliko", "hvala", "molim", "nije", "sam", "шта", "где", "хвала"]),
        "is": .init(script: .latin, letters: "ðþæ", words: ["og", "er", "ég", "þú", "það", "ekki", "hvar", "hvað", "takk", "við"]),
        "ga": .init(script: .latin, letters: "", words: ["agus", "is", "tá", "an", "na", "ní", "cá", "conas", "go", "raibh", "maith", "agat", "dia"]),
        "mt": .init(script: .latin, letters: "ċġħ", words: ["u", "huwa", "hija", "il", "ma", "jien", "int", "fejn", "kemm", "grazzi", "jekk"]),
        "mk": .init(script: .cyrillic, letters: "ќѓѕљњџј", words: ["и", "е", "не", "на", "да", "што", "каде", "колку", "благодарам", "ова", "сум"]),
        "bs": .init(script: .latin, letters: "čćđšž", words: ["je", "i", "se", "na", "da", "šta", "gdje", "koliko", "hvala", "molim", "nije", "sam"]),
        "be": .init(script: .cyrillic, letters: "ўі", words: ["і", "што", "гэта", "як", "дзе", "колькі", "дзякуй", "калі", "ласка", "не", "я"]),
        "cy": .init(script: .latin, letters: "ŵŷ", words: ["ac", "yn", "y", "mae", "dw", "chi", "ble", "faint", "diolch", "os", "gwelwch"]),
        "gl": .init(script: .latin, letters: "ñ", words: ["o", "os", "as", "e", "é", "que", "de", "non", "onde", "canto", "grazas", "ola", "vostede"]),
        "lb": .init(script: .latin, letters: "ë", words: ["an", "ass", "net", "ech", "du", "mir", "wou", "wéi", "vill", "merci", "mat"]),
        // 12 Nov 2026. A script of its own is enough for most; Arabic, Persian and Urdu share one, so
        // their own letters decide: Arabic ي ك ة; Persian and Urdu share پ چ گ ک ی, then Persian writes
        // ه where Urdu writes ہ, and only Urdu has ٹ ڈ ڑ ں ے. Latin-script
        // words that are common in a European language ("po", "na", "di", "sa", "em") are left out, so
        // an owner's Polish line is never taken for the other person's.
        // Bengali writes র where Assamese writes ৰ; Cantonese's own characters (嘅 唔 係 冇 哋) tell it from Mandarin.
        "ar": .init(script: .arabic, letters: "ةىيكأإؤ", words: ["في", "من", "على", "هل", "هذا", "هذه", "أنا", "أنت", "شكرا", "شكراً", "كم", "أين", "ماذا", "نعم", "إلى", "لو", "سمحت"]),
        "fa": .init(script: .arabic, letters: "پچژگکیه", words: ["است", "این", "آن", "من", "شما", "چه", "کجا", "چقدر", "ممنون", "مرسی", "بله", "می", "را", "که", "با", "هست", "خیلی", "لطفاً"]),
        "ur": .init(script: .arabic, letters: "پچگکیٹڈڑںےھہ", words: ["ہے", "ہیں", "کیا", "میں", "آپ", "کہاں", "کتنا", "کتنے", "شکریہ", "نہیں", "جی", "ہاں", "کے", "کی", "کا", "اور", "یہ", "وہ"]),
        "he": .init(script: .hebrew, letters: "", words: ["אני", "אתה", "את", "זה", "לא", "כן", "מה", "איפה", "כמה", "תודה", "בבקשה", "של", "עם", "יש", "אין"]),
        // Characters only Chinese uses (no spaces to find words by).
        "zh": .init(script: .han, letters: "的吗们这么没说谢吧您", words: []),
        // Kana particles; kanji alone still counts as Japanese, but less than as Chinese.
        "ja": .init(script: .kana, also: [.han], letters: "のはがをにでとも", words: []),
        "ko": .init(script: .hangul, letters: "", words: ["안녕하세요", "감사합니다", "네", "아니요", "어디", "얼마", "저", "제가", "뭐", "있어요", "없어요", "주세요"]),
        "hi": .init(script: .devanagari, letters: "", words: ["है", "हैं", "क्या", "मैं", "आप", "कहाँ", "कितना", "धन्यवाद", "नहीं", "हाँ", "का", "की", "के", "और", "यह"]),
        "bn": .init(script: .bengali, letters: "র", words: ["আমি", "আপনি", "কি", "কোথায়", "কত", "ধন্যবাদ", "না", "হ্যাঁ", "এটা", "আছে"]),
        "th": .init(script: .thai, letters: "", words: []),
        "ka": .init(script: .georgian, letters: "", words: ["და", "არის", "მე", "თქვენ", "სად", "რამდენი", "მადლობა", "არა", "კი", "ეს"]),
        "vi": .init(script: .latin, letters: "ơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ", words: ["không", "tôi", "bạn", "của", "có", "này", "ở", "đâu", "bao", "nhiêu", "cảm", "ơn", "được", "và", "anh", "chị", "gì"]),
        // Indonesian and Malay share most words; the ones each uses alone decide, and a tie is no guess.
        "id": .init(script: .latin, letters: "", words: ["yang", "ini", "itu", "tidak", "saya", "mana", "berapa", "terima", "kasih", "ada", "apa", "bisa", "tolong", "sudah", "belum", "kamu", "karena", "saja", "bagaimana"]),
        "ms": .init(script: .latin, letters: "", words: ["yang", "ini", "itu", "tidak", "saya", "mana", "berapa", "terima", "kasih", "ada", "apa", "boleh", "tolong", "sudah", "belum", "awak", "mahu", "kerana", "sahaja", "bagaimana", "encik"]),
        "fil": .init(script: .latin, letters: "", words: ["ang", "ng", "mga", "ikaw", "salamat", "saan", "magkano", "ito", "ba", "kayo", "opo", "oo", "naman", "siya", "kumusta"]),
        "sw": .init(script: .latin, letters: "", words: ["kwa", "wa", "asante", "wapi", "ngapi", "mimi", "wewe", "hapana", "ndiyo", "habari", "tafadhali", "nini", "hii", "sana", "kuna"]),
        // The 36 added later on 12 Nov 2026. Kazakh, Kyrgyz, Mongolian and Tajik by their own Cyrillic letters
        // (Kyrgyz and Mongolian have none of their own, so words decide); Pashto and Sindhi by theirs; Marathi
        // and Nepali, in Hindi's script, by their words. Common words of European languages are left out again
        // ("na", "ora", "ma", "va", "men", "ha", "ne", "та", "би").
        "af": .init(script: .latin, letters: "", words: ["ek", "jy", "julle", "baie", "dankie", "hoeveel", "asseblief", "hierdie"]),
        "hy": .init(script: .armenian, letters: "", words: ["ես", "դուք", "որտեղ", "որքան", "շնորհակալություն", "այո", "ոչ", "և", "է"]),
        "as": .init(script: .bengali, letters: "ৰৱ", words: ["মই", "আপুনি", "ক'ত", "কিমান", "নহয়", "হয়", "আছে"]),
        "ast": .init(script: .latin, letters: "", words: ["ye", "nun", "gracies", "ónde", "cuántu", "soi", "nesti", "esti", "pue", "voi", "ente", "tamién"]),
        "az": .init(script: .latin, letters: "ə", words: ["mən", "nə", "harada", "neçə", "təşəkkür", "zəhmət", "xahiş", "yox", "bəli", "və", "deyil"]),
        "my": .init(script: .myanmar, letters: "", words: []),
        "yue": .init(script: .han, letters: "嘅唔咗喺係冇啲佢嘢哋㩒嗰咩乜嚟俾", words: []),
        "gu": .init(script: .gujarati, letters: "", words: []),
        "ha": .init(script: .latin, letters: "ɓɗƙƴ", words: ["sannu", "nagode", "yaya", "nawa", "ina", "wannan", "allah", "magana", "kuma", "zan", "yi"]),
        "jv": .init(script: .latin, letters: "", words: ["aku", "kowe", "iki", "iku", "ing", "karo", "mangga", "matur", "nuwun", "pira", "ngendi", "wis", "arep", "kanggo", "panjenengan"]),
        "kn": .init(script: .kannada, letters: "", words: []),
        "kk": .init(script: .cyrillic, letters: "әғқңөұү", words: ["және", "емес", "қалай", "қанша", "рахмет", "өтінемін", "сіз", "бұл", "қайда", "иә", "жоқ"]),
        "ky": .init(script: .cyrillic, letters: "ңөү", words: ["жана", "эмес", "кандай", "канча", "рахмат", "сураныч", "сиз", "бул", "кайда", "ооба", "жок", "мен"]),
        "ml": .init(script: .malayalam, letters: "", words: []),
        "mi": .init(script: .latin, letters: "ō", words: ["kia", "ahau", "koe", "tēnā", "kei", "hea", "pēhea", "aroha", "atu", "ngā", "tēnei", "kōrua"]),
        "mr": .init(script: .devanagari, letters: "ळ", words: ["आहे", "आहेत", "मी", "तुम्ही", "काय", "कुठे", "किती", "नाही", "आणि", "हे", "ते"]),
        "mn": .init(script: .cyrillic, letters: "өү", words: ["байна", "энэ", "юу", "хаана", "хэд", "баярлалаа", "үгүй", "тийм", "болон"]),
        "ne": .init(script: .devanagari, letters: "", words: ["छ", "छन्", "म", "तपाईं", "कति", "छैन", "यो", "मेरो", "हुन्छ"]),
        "oc": .init(script: .latin, letters: "", words: ["soi", "sètz", "mercé", "mercés", "aquò", "òc", "aqueste", "aquesta", "vau", "parlatz", "sus"]),
        "or": .init(script: .odia, letters: "", words: []),
        "ps": .init(script: .arabic, letters: "ټډړښږځڅڼۍېګ", words: ["زه", "ته", "تاسو", "دا", "چېرته", "څومره", "مننه", "هو", "یم", "یې"]),
        "pa": .init(script: .gurmukhi, letters: "", words: []),
        "sd": .init(script: .arabic, letters: "ڄٻڀٽٺڊڍڏڙڦڪڳڱڻڇ۾ٿڌ", words: ["آهي", "آهيان", "مان", "توهان", "ڪٿي", "ڪيترو", "مهرباني"]),
        "so": .init(script: .latin, letters: "", words: ["waxaan", "waa", "iyo", "maya", "haa", "fadlan", "mahadsanid", "xagee", "immisa", "aad", "ku", "oo", "waxa"]),
        "tg": .init(script: .cyrillic, letters: "ӣӯҳҷғқ", words: ["ман", "шумо", "ин", "чӣ", "куҷо", "чанд", "ташаккур", "лутфан"]),
        "ta": .init(script: .tamil, letters: "", words: []),
        "te": .init(script: .telugu, letters: "", words: []),
        "uz": .init(script: .latin, letters: "ʻʼ", words: ["nima", "qayerda", "qancha", "rahmat", "iltimos", "yoʻq", "emas", "bilan", "salom", "kerak", "yaxshi"]),
        "yo": .init(script: .latin, letters: "ẹọṣ", words: ["báwo", "ibo", "kí", "wà", "èmi", "ìwọ"]),
        "am": .init(script: .ethiopic, letters: "", words: []),
        "lo": .init(script: .lao, letters: "", words: []),
        "lg": .init(script: .latin, letters: "", words: ["nze", "ggwe", "gyebale", "webale", "nnyo", "ssebo", "nnyabo", "mwattu", "wano", "bulijjo"]),
        "sn": .init(script: .latin, letters: "", words: ["ndini", "mhoro", "ndatenda", "maita", "zvakanaka", "ndapota", "kupi", "marii", "hongu", "kwete"]),
        // Central Kurdish writes ە ێ ۆ ڕ ڵ, which Persian and Urdu don't.
        "ckb": .init(script: .arabic, letters: "ڕڵۆێەڤ", words: ["تۆ", "ئێوە", "کوێ", "چەند", "سوپاس", "بەڵێ", "نەخێر", "ئەمە"]),
        "wo": .init(script: .latin, letters: "", words: ["maa", "ngi", "dama", "bëgg", "jërëjëf", "ñaata", "waaw", "déedéet", "nanga", "yow", "ndax"]),
        "zu": .init(script: .latin, letters: "", words: ["sawubona", "ngiyabonga", "yebo", "ngicela", "sicela", "kuphi", "malini", "wena", "futhi", "kodwa"]),
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
    /// saying instead of translating it", ADR-574). It used to be "Doddy, …" or "hey Doddy …" at the
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
            "obat", "ubat", "klinik", "ospital", "gamot", "daktari",
            "의사", "병원", "약국", "처방", "알레르기", "구급차", "응급", "임신",
            "डॉक्टर", "डाक्टर", "अस्पताल", "दवा", "एलर्जी", "एम्बुलेंस", "गर्भवती",
            "ডাক্তার", "হাসপাতাল", "ওষুধ", "অ্যাম্বুলেন্স",
            "ڈاکٹر", "ہسپتال", "اسپتال", "دوائی", "دکتر", "پزشک", "بیمارستان", "دارو",
            "ექიმ", "საავადმყოფო", "წამალ", "აფთიაქ",
            "hospitaal", "medisyne", "həkim", "xəstəxana", "dərman", "shifokor", "kasalxona", "dorixona",
            "likita", "asibiti", "magani", "udokotela", "isibhedlela", "chiremba", "chipatara", "mushonga",
            "omusawo", "eddwaliro", "eddagala", "doktoor", "loppitaan", "ሐኪም", "ሆስፒታል", "መድኃኒት", "دکتۆر", "نەخۆشخانە",
            "dhakhtar", "isbitaal", "daawo", "tākuta", "hōhipera", "rongoā", "mètge", "espital", "médicu", "melecina",
            "բժիշկ", "հիվանդանոց", "դեղատուն", "дәрігер", "аурухана", "дарыгер", "оорукана", "эмч", "эмнэлэг", "духтур", "беморхона",
            "மருத்துவ", "డాక్టర్", "ఆసుపత్రి", "रुग्णालय", "ડૉક્ટર", "હોસ્પિટલ", "દવા", "ਡਾਕਟਰ", "ਹਸਪਤਾਲ", "ਦਵਾਈ",
            "ವೈದ್ಯ", "ಡಾಕ್ಟರ್", "ಆಸ್ಪತ್ರೆ", "ഡോക്ടർ", "ആശുപത്രി", "മരുന്ന്", "औषधि", "ডাক্তৰ", "ଡାକ୍ତର", "ډاکټر", "روغتون", "درمل", "ڊاڪٽر",
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
            "pengacara", "peguam", "pengadilan", "mahkamah", "paspor", "pulis", "wakili", "mahakama", "mkataba", "pasipoti",
            "경찰", "변호사", "법원", "재판", "계약", "여권", "비자", "대사관",
            "पुलिस", "वकील", "अदालत", "पासपोर्ट", "পুলিশ", "উকিল", "আদালত", "পাসপোর্ট",
            "پولیس", "پلیس", "وکیل", "عدالت", "دادگاه", "پاسپورت",
            "პოლიცი", "ადვოკატ", "სასამართლო", "ხელშეკრულებ", "პასპორტ", "ვიზა", "საელჩო",
            "prokureur", "vəkil", "məhkəmə", "politsiya", "lauya", "kotu", "booliis",
            "amaphoyisa", "iphoyisa", "ummeli", "mapurisa", "gweta", "poliisi", "looya", "ፖሊስ", "ጠበቃ", "پۆلیس", "پارێزەر",
            "qareen", "maxkamad", "pirihimana", "rōia", "kōti", "abogáu",
            "ոստիկան", "փաստաբան", "դատարան", "милиция", "милиса",
            "காவல்", "పోలీస్", "पोलीस", "પોલીસ", "ਪੁਲਿਸ", "ਪੁਲੀਸ", "ಪೊಲೀಸ್", "പോലീസ്", "प्रहरी", "ପୋଲିସ", "وڪيل", "محکمه",
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
            "pinjaman", "utang", "hutang", "bangko", "benki", "mkopo",
            "은행", "대출", "빚", "보증금",
            "बैंक", "कर्ज", "क़र्ज़", "ऋण", "ব্যাংক", "ঋণ",
            "بینک", "بانک", "وام", "قرض", "بنك",
            "ბანკ", "სესხ",
            "skuld", "borc", "qarz", "bangi", "deyn", "bashi", "banki", "pēke", "prèst", "bancu", "préstamu",
            "ibhange", "isikweletu", "bhangi", "chikwereti", "bbanka", "ebbanja", "ባንክ", "ብድር", "قەرز",
            "բանկ", "վարկ", "несие", "қарыз", "насыя", "карыз", "қарз", "бонк",
            "வங்கி", "கடன்", "బ్యాంక్", "બેંક", "ਬੈਂਕ", "ਕਰਜ਼", "ಬ್ಯಾಂಕ್", "ബാങ്ക്", "വായ്പ", "ବ୍ୟାଙ୍କ", "بئنڪ",
        ],
    ]

    /// Found anywhere in the text, not only at a word's start: Chinese, Japanese and Thai have no
    /// spaces between words, Arabic and Hebrew join "the" and "in" to the front of a word
    /// (المستشفى, בבית החולים), and some are two words (rumah sakit, bác sĩ). Long or rare enough not
    /// to sit inside an everyday word: no Hebrew חוב (it is inside רחוב, street), no Thai ศาล (a shrine).
    static let contained: [Topic: [String]] = [
        .health: [
            "医生", "大夫", "医院", "醫院", "药", "藥", "过敏", "救护车", "怀孕", "处方",
            "医者", "病院", "薬", "アレルギー", "救急車", "妊娠", "処方",
            "แพทย์", "โรงพยาบาล", "ร้านขายยา", "ใบสั่งยา", "รถพยาบาล", "ตั้งครรภ์",
            "طبيب", "دكتور", "مستشفى", "دواء", "صيدلي", "إسعاف", "وصفة طبية",
            "רופא", "בית חולים", "בית החולים", "תרופ", "מרשם", "אמבולנס", "בהריון",
            "rumah sakit", "bác sĩ", "bệnh viện", "thuốc", "dị ứng", "cấp cứu", "mang thai", "có thai",
            "醫生", "ဆရာဝန်", "ဆေးရုံ", "ທ່ານໝໍ", "ໂຮງໝໍ",
        ],
        .law: [
            "警察", "律师", "律師", "法院", "合同", "护照", "護照", "签证", "大使馆",
            "弁護士", "裁判", "契約", "パスポート", "ビザ", "大使館",
            "ตำรวจ", "ทนาย", "สัญญาเช่า", "หนังสือเดินทาง", "วีซ่า", "สถานทูต",
            "شرطة", "بوليس", "محامي", "محكمة", "جواز سفر", "تأشيرة", "سفارة",
            "ຕຳຫຼວດ",
            "משטרה", "שוטר", "עורך דין", "עורכת דין", "בית משפט", "בית המשפט", "חוזה", "דרכון", "ויזה", "שגרירות",
            "cảnh sát", "công an", "luật sư", "tòa án", "hợp đồng", "hộ chiếu", "thị thực", "đại sứ quán",
        ],
        .money: [
            "银行", "銀行", "贷款", "借钱", "押金",
            "ローン", "借金", "敷金",
            "ธนาคาร", "เงินกู้", "หนี้", "เงินมัดจำ",
            "البنك", "قرض", "عربون",
            "בנק", "הלוואה", "משכנתא",
            "ngân hàng", "khoản vay", "vay tiền", "đặt cọc", "nợ",
            "借錢", "ဘဏ်", "ທະນາຄານ",
        ],
    ]

    /// Everyday words a stem would wrongly catch ("polis", "polic", "policie", "pill"; Italian
    /// "ospitale", hospitable, for Filipino "ospital").
    static let notTopics: Set<String> = [
        "polish", "polished", "polishing", "policy", "policies", "pillow", "pillows",
        "ospitale", "ospitali", "ospitalità",
    ]

    /// The first topic heard in the text, health first.
    public static func topic(in text: String) -> Topic? {
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init).filter { !notTopics.contains($0) }
        for topic in [Topic.health, .law, .money] {
            let list = stems[topic] ?? []
            if words.contains(where: { word in list.contains { stem in
                word.hasPrefix(stem)
            } }) { return topic }
            if (contained[topic] ?? []).contains(where: { lower.contains($0) }) { return topic }
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
