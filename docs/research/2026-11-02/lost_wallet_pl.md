<!-- Research for ADR-686 (lost wallet by voice), 2 Nov 2026. Written by a research agent from official pages and statutes
     read that day; every item says whether it is confirmed. Nothing was tested inside the iOS app. The six gov.pl addresses
     and the Dokumenty Zastrzeżone address the checklist opens were fetched again by hand afterwards, and each page's own
     title was read. -->
# Lost wallet / ID in Poland: research for Doddy's checklist card

Checked on **2 November 2026**. Every fact below comes from a page or statute read today. For gov.pl service pages, the date shown is the page's own "Ostatnia aktualizacja" (last updated).

**Labels**
- **CONFIRMED**: stated in an official source read today.
- **PARTIAL**: official sources support it, but not in plain words, or two official sources disagree.
- **NOT CONFIRMED**: no official source found today. Doddy must not state it as fact.

**Limits of this check**
- `info.mobywatel.gov.pl` (the mObywatel help site) blocked every automated request today ("The request is blocked", HTTP 403). Facts about the app therefore come from gov.pl / Ministerstwo Cyfryzacji (MC) articles and from the official mObywatel rulebook PDFs on gov.pl.
- `mos.cudzoziemcy.gov.pl` returned HTTP 503.
- Statutes were read as consolidated texts from the Sejm ELI API (`api.sejm.gov.pl`).
- Nothing here was tested inside the iOS app.

---

## 1. Lost or stolen ID card (dowód osobisty)

### 1a. Reporting in the mObywatel app

**In-app path: PARTIAL.** Official sources use slightly different wording for the entry point.
- MC (24.06.2025): choose **"Załatw sprawę"** from the list of services, then the **"Dowód osobisty"** tab, then fill in and send the report.
  - Source: https://www.gov.pl/web/cyfryzacja/nowosci-w-mobywatelu-szybkie-zgloszenie-utraty-dowodu-osobistego-i-sprawdzanie-jego-waznosci-w-aplikacji
- MC (21.04.2026): suspend and cancel are in **"Załatw sprawę (kategoria Sprawy urzędowe)"**.
  - Source: https://www.gov.pl/web/cyfryzacja/kpo-napedza-mobywatela-zgubiony-lub-skradziony-dokument-zastrzezesz-go-w-aplikacji-dzieki-srodkom-unijnym
- Official app document "Informacje o publicznej aplikacji mobilnej mObywatel" (PDF dated 18.08.2026), §43:
  - Steps: log in, then "Załatw sprawę", then "dowód osobisty", then **"unieważnij swój dowód"**, then follow the on-screen instructions.
  - Suspension (§44) is in the same place: **"Zawieś swój dowód lub cofnij zawieszenie"**.
  - Source: https://www.gov.pl/attachment/c85bf128-ae03-4b9b-a394-c78cab08018d
- Rulebook annex "Załącznik nr 4 do Regulaminu" (PDF dated 02.09.2026) gives step b) as **"Złóż wniosek"** instead of "Załatw sprawę".
  - Source: https://www.gov.pl/attachment/79bb0dbf-099e-41f2-8255-30a6607f3393
  - **Implication for Doddy:** don't promise exact button labels. Say: "In mObywatel, open Usługi and find 'Unieważnij swój dowód' (under Załatw sprawę → Dowód osobisty)."

**Requirements: CONFIRMED** (Załącznik nr 4, §2). The person must:
- be an adult;
- have a valid ID card;
- have the mObywatel basic certificate (mDowód) in the app;
- have an active Profil Zaufany;
- have an ePUAP account and an e-Doręczenia inbox ("skrzynkę eDoręczeń").

The MC article (24.06.2025) also says the ePUAP inbox is required.

**Effect: CONFIRMED.**
- MC (24.06.2025): "Unieważnienie dowodu jest natychmiastowe i nieodwracalne." The report goes to a gmina office that the system assigns automatically.
- MC (21.04.2026): it takes effect immediately, "także w nocy i dni wolne od pracy", with no official involved.

**Identity theft variant: CONFIRMED.**
- In the app it is a separate service: "Unieważnij swój dowód – kradzież tożsamości" (Załącznik nr 4, §9).
- On gov.pl the person must make the theft plausible, for example with a letter or email from a company about a data leak.
- Source: https://www.gov.pl/web/gov/zglos-nieuprawnione-wykorzystanie-swoich-danych-osobowych-kradziez-tozsamosci--uniewaznij-dowod (updated 31.12.2025)

### 1b. Reporting on gov.pl: CONFIRMED

Source page, updated 11.02.2026: https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-swojego-dowodu-osobistego-uniewaznij-dowod

- **Name and purpose:** "Zgłoś utratę lub uszkodzenie swojego dowodu osobistego – unieważnij dowód". The page says to report it "jak najszybciej w urzędzie gminy, przez Internet lub w aplikacji mObywatel".
- **Button:** "WYŚLIJ ZGŁOSZENIE" opens https://www.mobywatel.gov.pl/twoje-dane/rdo/twoj-dokument
- **Login:** "potrzebujesz profilu zaufanego, certyfikatu kwalifikowanego albo e-dowodu."
  - You sign through the e-podpis service on pz.gov.pl, using an SMS code sent to the phone linked to your Profil Zaufany.
- **Since 1 January 2026:** "tę sprawę załatwisz już tylko za pośrednictwem e-Doręczeń". The person needs an e-Doręczenia address: https://www.gov.pl/web/gov/uzyskaj-adres-do-e-doreczen-u-publicznego-dostawcy-uslugi-e-doreczen
- **Timing:**
  - "Status twojego dowodu od razu się zmieni w Rejestrze Dowodów Osobistych."
  - "Nawet jeśli zrobisz to w dniu, w którym urząd nie pracuje, albo w nocy."
- **Certificate of loss:** it arrives in the e-Doręczenia inbox. It is valid until the new ID is issued, but "nie dłużej niż 2 miesiące", and it "nie jest dokumentem tożsamości".
- **Cost:** free.
- **Qualified e-signature:** if a private provider's qualified signature is loaded on the e-dowód, the person must contact that provider. The service does not cancel it.

### 1c. Reporting in person, at the police, or abroad: CONFIRMED

Source: the same gov.pl page, plus the ID Card Act (Dz.U. 2025 poz. 1753), Art. 47 and 50.

- **Gmina office:** "W dowolnym urzędzie gminy" (any gmina). "Urzędnik od razu unieważni twój dowód osobisty."
  - Bring another ID document, such as a passport, if you have one.
- **Police, for theft:** "Jeżeli twój dowód osobisty został ukradziony, wystarczy, że zgłosisz to policji." You then don't need to go to the gmina.
  - "Dowód zostanie unieważniony z dniem zgłoszenia tego faktu policji." Statute: Art. 47 ust. 9 and Art. 50 ust. 3 pkt 5d.
- **Abroad:** at a Polish consulate, in person, by post or by fax. The consul forwards it to the issuing gmina, which cancels the ID "najszybciej, jak to możliwe". See section 8.
- **Legal duty:** the holder must report a loss "niezwłocznie" (Art. 47 ust. 1).

### 1d. Can a cancelled ID be "un-cancelled"? No. CONFIRMED

- MC (24.06.2025): "Unieważnienie dowodu jest natychmiastowe i nieodwracalne."
- MC (21.04.2026), answering "Czy unieważnienie można cofnąć?": "Nie. Unieważnienie sprawia, że dokument traci ważność na stałe."
- ID Card Act, Art. 49 ust. 4: a holder who finds an ID already reported lost must hand it in "niezwłocznie" at any gmina or to a consul.
- Art. 49 ust. 5: a public official who is shown an ID reported as lost must seize it.

**The only reversible option is suspension (zawieszenie): CONFIRMED.**
- Source: https://www.gov.pl/web/gov/zglos-zawieszenie-lub-cofnij-zawieszenie-swojego-e-dowodu (updated 31.12.2025)
- It works only for an **e-dowód issued after 4 March 2019**.
- Suspension lasts at most 14 calendar days. If it is not lifted, the ID is "unieważniony na zawsze".
- The page warns: "NIE zawieszaj e-dowodu, jeśli masz pewność, że już go nie odzyskasz."
- Channels: the app, online with Profil Zaufany, or any gmina office.
- How to recognise an e-dowód: it has a CAN number in the bottom-right corner (MC, 21.04.2026).

**Checking status: CONFIRMED.**
- In the app ("Sprawdź dowód"), or online: https://www.gov.pl/web/gov/Sprawdz-czy-dowod-osobisty-jest-uniewazniony-lub-zawieszony (updated 10.07.2025)
- Needs Profil Zaufany or e-dowód. The answer is immediate.

### 1e. Applying for a new ID: CONFIRMED

Source page, updated 11.02.2026: https://www.gov.pl/web/gov/uzyskaj-dowod-osobisty

- **Order:** "Otrzymasz nowy dowód po unieważnieniu starego, zgłoszonego dokumentu." Report the loss first.
- **Online:**
  - Form: https://www.mobywatel.gov.pl/form-viewer/?name=wniosek-o-wydanie-dowodu-osobistego
  - Login through login.gov.pl. Sign with Profil Zaufany, e-dowód or a qualified signature.
  - The app also has "Uzyskaj dowód dla siebie" (Załącznik nr 4).
  - Within **30 days** the person must visit the office they chose, to give fingerprints and a handwritten signature. Otherwise the application is not processed.
  - Confirmation goes to the e-Doręczenia inbox and to the email given in the application. That email also receives the application number and the name of the office.
- **In person:** at any gmina office, regardless of registered address. No paper form is needed.
- **Cost:** "Usługa jest bezpłatna."
- **Time:**
  - In person: up to 30 days from the application.
  - Online: up to 30 days from the fingerprint visit.
  - It can take longer in special cases.
- **Collection:** in person, at the office that accepted the application.
  - Bring the current ID or a valid passport.
  - The page adds: if you have neither, another photo ID, such as a driving licence (in the "documents to bring" section).
  - A proxy may collect only in limited cases, such as illness. Being abroad is not a reason.
  - Consulates do not accept applications and do not hand out ID cards.
- **Is it ready?**
  - Online, with the application number: https://www.gov.pl/web/gov/sprawdz-czy-dowod-osobisty-jest-gotowy
  - In the app: the "Odbiór dowodu" service (MC article "Zarządzanie dowodem osobistym w mObywatelu").
  - **NOT CONFIRMED:** whether the app sends a push notification when the ID is ready. The gov.pl page only describes email alerts for e-Doręczenia messages.
- **Photo:** colour, 35×45 mm.
  - Online: at least 492×633 px, at most 2.5 MB.
  - In person: printed on photo paper.

### 1f. mDowód after the physical ID is cancelled: PARTIAL, not confirmed in plain words

What is confirmed:
- mDowód is a separate document with its own series, number and expiry date. It is issued for 5 years.
  - Sources: mObywatel Act, Art. 7 ust. 1–2 (Dz.U. 2024 poz. 1275); MC explainer: https://www.gov.pl/web/cyfryzacja/dokumenty-tozsamosci-ktore-musisz-znac-ministerstwo-cyfryzacji-wyjasnia-czym-sa-mdowod-e-dowod-dowod-osobisty-dowod-cyfrowy-i-elektroniczny
- The statute invalidates the mDowód automatically only in three cases:
  - death;
  - loss of Polish citizenship (Art. 7 ust. 3);
  - the user not updating data when the app asks (Art. 8 ust. 3).
- Cancelling the plastic ID is **not listed** as a reason. The 2025 amendment (Dz.U. 2025 poz. 1019) did not change this.
- mDowód cannot be used to cross a border (Art. 7 ust. 5). Per MC, it also cannot be used to apply for a new ID card.

**NOT CONFIRMED:** no official plain-language statement was found today saying "your mDowód stays valid after you cancel your ID". The help site that might say so was unreachable.

**What Doddy should say:** "Check in mObywatel whether your mDowód shows 'dokument ważny'." Don't assert that it does.

**Different case, if the phone was lost too:** the mObywatel certificate can be revoked by calling **+48 42 253 54 74** ("czynnego całą dobę"), or by activating the app on another phone, which revokes the old one automatically.
- Sources: app info PDF §1.3; MC, 29.01.2025: https://www.gov.pl/web/cyfryzacja/bezpieczenstwo-korzystania-z-e-dowodu-i-mdowodu--to-warto-wiedziec2

---

## 2. PESEL reservation (zastrzeżenie numeru PESEL)

**In the app: CONFIRMED** (MC, 17.08.2026)
1. Log in to mObywatel.
2. Tap **"Usługi"** at the bottom of the screen.
3. Choose **"Zastrzeż PESEL"**.
4. Tap the button or switch and confirm.

- Source: https://www.gov.pl/web/cyfryzacja/chron-swoje-dane-z-mobywatelem-zastrzez-numer-pesel-w-aplikacji
- The service turns on automatically once mDowód is added (app info PDF §30).

**Online: CONFIRMED.**
- Page (updated 29.10.2024): https://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel-lub-cofnij-zastrzezenie
- Button: https://www.mobywatel.gov.pl/twoje-dane/rzp-pesel
- Login: Profil Zaufany, qualified signature, e-dowód, **or online-banking login**.

**In person: CONFIRMED.**
- At any gmina office, with an ID card or passport.
- By statute, banks, SKOKs and Poczta Polska *may* also offer it (Population Register Act, Art. 23f; Dz.U. 2026 poz. 384). They are not required to.

**Rules: CONFIRMED** (gov.pl page plus Art. 23d–23e)
- Adults only.
- Free. Takes effect immediately.
- It can be lifted indefinitely, or **temporarily, with a date and time** when it switches back on automatically (Art. 23d ust. 3).
- After lifting, it cannot be reserved again for **30 minutes** (Art. 23d ust. 5).

**What it does: CONFIRMED.**
- gov.pl: "From 1 June 2024" financial institutions such as banks must check the reservation when signing, for example, a loan agreement.
- MC (04.08.2026) names banks, SKOKs, notaries and telecoms as checking it. If someone takes out a debt using a reserved PESEL, the owner "nie będzie musiał go spłacać".
  - Source: https://www.gov.pl/web/cyfryzacja/jedno-klikniecie-przed-urlopem-moze-uchronic-przed-kosztownym-problemem-zastrzez-pesel-zanim-wyjedziesz
- It does **not** affect:
  - the validity of an ID card or passport;
  - doctors and prescriptions;
  - ATMs and bank transfers;
  - travel;
  - Profil Zaufany;
  - dealing with offices.

**Automatic reservation after losing an ID: CONFIRMED.**
- The gov.pl ID-loss page: "Jeśli masz ukończone 18 lat i zgłosisz utratę dowodu osobistego, twój numer PESEL zostanie zastrzeżony z urzędu."
- Statute: Art. 23g ust. 1 pkt 1 does this when an ID is cancelled after a loss reported under Art. 47 of the ID Card Act, or after an identity-theft report.
- **PARTIAL:** whether a report made **only to the police** (Art. 47 ust. 9) also triggers it is not stated plainly.
- **What Doddy should say:** "Check the PESEL status in mObywatel (Usługi → Zastrzeż PESEL). If it isn't reserved, reserve it."

**Is it a good idea after losing an ID? Yes, per the official sources.**
- After a loss report it happens automatically.
- MC recommends keeping PESEL reserved by default ("domyślnie PESEL był zastrzeżony") and lifting it only temporarily, for a loan or a bank account (MC, 17.08.2026).
- The app also shows "Twoje zmiany" (reservation history) and **"Kto sprawdzał Twój PESEL"** (who checked the number). This is useful after a loss (app info PDF §71.23).

**Help line:** zastrzeganie-pomoc@cyfra.gov.pl, **+48 422 535 460** (gov.pl page).

---

## 3. Bank cards

**Shared line +48 828 828 828: CONFIRMED.** Sources read today:
- https://zastrzegam.pl/o-systemie/
- https://zastrzegam.pl/regulamin-uslugi/
- https://zastrzegam.pl/uczestnicy/

**How it works:**
- Run by **Związek Banków Polskich (ZBP)**.
- It is a speech-recognition voice menu (IVR). It asks **only for the bank's name**, then puts you through to that bank's own hotline. The bank does the blocking under its own procedures.
- **One call = one bank.** For cards from another bank, call again.
- It asks for no name, PESEL or other personal data. The bank's staff will ask for identification after the transfer.

**Availability and cost:**
- "7 dni w tygodniu 24 godziny na dobę" (Regulamin §3.1).
- **From abroad:** "Tak. Do numeru 828 828 828 wystarczy dodać prefiks +48."
- The service is free. The caller pays the normal call charge of their mobile operator (Regulamin §5).
- If the call fails, the regulations tell you to contact the bank directly (§4.1).

**Which banks:**
- The official participant page shows logos only: Millennium, BNP Paribas, BOS, Citi Handlowy, Credit Agricole, DNB, Getin Bank, BPS, ING, Inteligo, Bank BFG, Pekao, PKO, Plus Bank, Santander Bank Polska, Santander Consumer Bank, SGB, KBS (Krakowski Bank Spółdzielczy).
- **PARTIAL:** the list looks out of date.
  - Most logo files date from 2021; KBS was added in 2024.
  - It shows the Getin and Santander Bank Polska brands, while ZBP's own document-blocking list (section 4) names VeloBank and Erste Bank Polska.
  - Several large banks (for example mBank and Alior) do not appear.
- **What Doddy should say:** "If your bank isn't recognised, use your bank's app or the number on its website."

**Temporary lock vs. permanent block (zastrzeżenie): CONFIRMED** for the banks checked.
- mBank (https://www.mbank.pl/bezpieczenstwo/sprawdz-co-robic/):
  - Use the temporary block "gdy nie masz pewności, gdzie jest Twoja karta". You unblock it the same way.
  - "Zastrzeżenie karty jest nieodwracalne – nikt już z niej nie skorzysta."
- PKO BP (https://www.pkobp.pl/pomoc-kontakt/karty-platnosci/jak-zablokowac-zastrzec-karte):
  - A temporary block can be lifted. After zastrzeżenie, the bank recommends ordering a new card.
  - Hotline: 800 302 302 in Poland, **+48 81 535 60 60** from abroad.
- Bank app paths and hotline numbers differ per bank. Doddy should not hard-code them without a per-bank source.
- **Rule for Doddy:** wallet lost or stolen → permanent block (zastrzeżenie). Card probably just mislaid at home → temporary lock.

---

## 4. Dokumenty Zastrzeżone (ZBP's database of blocked documents)

**What it is: CONFIRMED.** Source: https://dokumentyzastrzezone.pl/system-dz/
- A database of lost and stolen documents, run by ZBP since 1997.
- A report made at one bank goes to the central database. From there it reaches "wszystkich banków, operatorów telefonii komórkowych oraz tysięcy innych firm i instytucji", in near real time.
- The full list of participants is kept secret.

**How to report: CONFIRMED.** Source: https://dokumentyzastrzezone.pl/zastrzeganie-dokumentow/
- At a branch of your own bank, or by phone at **828 828 828** "w wielu bankach".
- People without a bank account can use a bank that accepts reports from everyone: https://dokumentyzastrzezone.pl/lista-bankow-zastrzegajacych-dokumenty/
  - This list includes PKO BP, Bank Pocztowy, BPS, BNP Paribas, Credit Agricole, Erste Bank Polska, Plus Bank, Santander Consumer, SGB, VeloBank, BGK and many cooperative banks.
- Also possible through bik.pl (if you already had an account there) or the mObywatel app.
- The site's own phone number, 22 48 68 422, does **not** take reports.

**In mObywatel: CONFIRMED.** Source: ZBP/DZ article of 09.02.2026, quoting info.mobywatel.gov.pl: https://dokumentyzastrzezone.pl/zgubiles-dowod-osobisty-zastrzez-go-jednym-kliknieciem-nowa-funkcja-w-aplikacji-mobywatel-bezpiecznie-i-natychmiastowo/
1. Log in.
2. Go to "Usługi", category **"Ochrona danych"**, then **"Zastrzeż dokument"**.
3. Tap "Dowód osobisty", then "Zastrzeż dowód", then "Potwierdź".

- Requirements: adult, app version 4.75.0 or later, mDowód.
- A block made in the app can be lifted **only in the app**. A block made at a bank must be lifted at that bank. The app info PDF (§71.39) says the same.
- **PARTIAL:** which documents can be blocked in the app.
  - ZBP (Feb 2026): ID card and passport.
  - MC (21.04.2026) and the MC article "Twoje dane wyciekły": ID card, passport **and driving licence**.

**Still relevant now that the ID can be cancelled through mObywatel? Yes. CONFIRMED.**
- The gov.pl ID-loss page still says: "Zgłoś utratę dowodu w banku, nawet jeśli nie masz konta bankowego." It links to the ZBP list.
- MC (21.04.2026) calls it "dodatkowe zabezpieczenie", which you can lift at any time.
- It is a different system from the state ID register and the PESEL reservation. It reaches private companies such as banks, telecoms and rental firms.

---

## 5. Theft and the police

**When to call 112: CONFIRMED.** Source (updated 17.04.2023): https://www.gov.pl/web/numer-alarmowy-112/co-zglaszac
- "DZWOŃ tylko w nagłych, wymagających interwencji służb ratowniczych sytuacjach."
- Situations listed include "kradzieże, włamania" and "rozboje i inne przypadki użycia przemocy".
- **Doddy's reading (not an official quote):** call 112 when there is danger or an urgent need for police right now, such as a robbery, violence, or a thief still nearby. A wallet found missing later is reported at a police station.

**Reporting a crime: CONFIRMED.** Source (updated 10.04.2026): https://www.gov.pl/web/gov/zglos-przestepstwo
- Report in person "w dowolnej jednostce policji", or at a prosecutor's office during working hours.
- A written report can be sent "mailem, faksem lub pocztą na adres policji albo prokuratury". The page gives no central address or e-form.
- Free.

**Online report form: NOT CONFIRMED.** No national online crime-report form was found on gov.pl or policja.pl today. Doddy should not say one exists.

**What to bring: CONFIRMED** (same page)
- A photo ID, for example an ID card, driving licence or passport.
- Documents that identify stolen items, such as serial numbers.
- Medical records, if the person was treated.
- If the ID itself was stolen, mDowód satisfies any legal identity requirement in Poland (mObywatel Act, Art. 7 ust. 4). Exceptions: crossing a border, and (per MC) applying for a new ID.

**A police report also handles some documents: CONFIRMED.**
- A stolen ID card is cancelled on the day of the police report (section 1c).
- A stolen passport already reported to the Polish police does not need a separate report (gov.pl passport page).

---

## 6. Driving licence (prawo jazdy)

**Report and replacement: CONFIRMED.** Source (updated 10.07.2023): https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-prawa-jazdy
- Where: the city office of a city with county rights, the district office (dzielnica) in Warsaw, or the starostwo (county office) where you live.
- Online through ePUAP: https://epuap.gov.pl/wps/portal/strefa-klienta/katalog-spraw/motoryzacja-i-transport/wymiana-prawa-jazdy/wydanie-wtornika-prawa-jazdy
  - Needs Profil Zaufany or a qualified certificate.
- Duplicate (wtórnik): **100 zł**. Needs an electronic photo of 480×615 px, at most 100 kB.
- Time: up to 9 working days.

**Deadline: CONFIRMED.** Drivers Act, Art. 18 ust. 1 (Dz.U. 2025 poz. 1226): the holder must tell the starosta about the loss **"w terminie 30 dni"**.

**Carrying the licence in Poland: CONFIRMED.**
- Not required for holders of a **Polish** licence, since **5 December 2020** (not 2018).
- The Ministry of Infrastructure, 04.12.2020: drivers with a Polish licence are exempt "z obowiązku posiadania przy sobie i okazywania dokumentu podczas kontroli drogowej na terytorium Polski". Police check the Central Register of Drivers instead.
  - Source: https://www.gov.pl/web/infrastruktura/ulatwienia-dla-kierowcow-wchodza-w-zycie
- The current Road Traffic Act, Art. 38 ust. 1 pkt 1 (Dz.U. 2024 poz. 1251), still requires carrying the licence only when it is *not* a Polish licence.
- **mPrawo Jazdy** exists in the app (app info PDF §13).
- What changed in 2018 was not researched.

**Driving while waiting for the duplicate: NOT CONFIRMED.**
- The gov.pl page only says "nie możesz prowadzić pojazdów bez ważnego prawa jazdy" (you need a valid licence entitlement).

**Abroad: PARTIAL.**
- The exemption covers only "na terytorium Polski".
- No official source today says whether mPrawo Jazdy is accepted abroad. Doddy should say to carry the physical licence abroad and not claim mPrawo Jazdy works there.

---

## 7. Passport

**In Poland: CONFIRMED.** Source (updated 04.06.2024): https://www.gov.pl/web/gov/zglos-utrate-lub-zniszczenie-paszportu
- **Online form (loss in Poland):** https://moj.gov.pl/uslugi/engine/ng/index?xFormsAppName=ZglosUtrateUszkodzenieDokumentuPaszportowego&xFormsOrigin=EXTERNAL&nfc_rodzajZgloszenia=UtrataWKraju
  - Other variants of the same form: `UszkodzenieWKraju`, `UtrataZaGranica`, `UszkodzenieZaGranica`.
  - Login: Profil Zaufany, e-dowód or a bank account. You confirm with an e-signature.
- **In the app:** an adult can cancel their own biometric or temporary passport in mObywatel, from Poland or abroad.
  - Sources: MC "Zarządzanie dowodem osobistym w mObywatelu": https://www.gov.pl/web/cyfryzacja/zarzadzanie-dowodem-osobistym-w-mobywatelu--sprawdz-jakie-sprawy-zalatwisz-w-aplikacji ; MC 21.04.2026
  - Passports of children or wards, and diplomatic or service passports, cannot be cancelled in the app.
- **In person:** at any passport office (punkt paszportowy, run by the voivode's office). Bring an ID card or other photo ID.
- **Theft:** if already reported to the Polish police, there's no need to report again. The passport was cancelled on the day of the police report.
- **Effect:** immediate, including at night, and irreversible: "unieważnienia nie będzie można cofnąć".
- **Cost:** the report is free. A new passport costs **140 zł** without discounts.
- **If found later:** report it to a passport office or the police. Abroad, take it to a consulate.

**Abroad: CONFIRMED.**
- Report at a Polish consulate. No appointment is needed just to report. An honorary consul cannot accept the report.
  - Source: https://www.gov.pl/web/wielkabrytania/zgloszenie-utraty-paszportu
- The consul can issue a **temporary passport** to return home, after confirming identity and citizenship. It is valid for at most 365 days.
  - Source: https://www.gov.pl/web/dyplomacja/paszporty
- The temporary passport fee depends on the consulate. **NOT CONFIRMED** here.

---

## 8. Losing things abroad

- **ID card:** report to any Polish consul, in person, by post or by fax. It can also be done online or in the app.
  - Paper form (PDF): https://www.gov.pl/attachment/af25d236-7a55-4cf5-95e3-e6016c5a6938
  - Find a consulate: https://www.gov.pl/web/dyplomacja/polskie-przedstawicielstwa-na-swiecie
  - The consul forwards the report to the issuing gmina, which cancels the ID "najszybciej, jak to możliwe". Statute: Art. 47a.
  - A new ID cannot be applied for or collected at a consulate; it can be done after returning to Poland (gov.pl "Uzyskaj dowód osobisty").
  - Sources: the gov.pl ID-loss page; https://powroty.gov.pl/utrata-dokumentow-za-granica-jak-postepowac-w-takiej-sytuacji/ (13.10.2025). Powroty also recommends telling the police if theft is suspected.
- **Getting home:** a temporary passport from the consul (section 7).
- **Cards:** call **+48 828 828 828**, which works from abroad (section 3), or the bank's international number (for example, PKO BP: +48 81 535 60 60).

---

## 9. mObywatel links, deep links and the App Store

- **App Store: CONFIRMED** through Apple's lookup API today.
  - Name: mObywatel. ID **1339613469**. Bundle ID `pl.nask.mObywatel`. Seller: Ministerstwo Cyfryzacji.
  - Version 4.93.1, released 30.10.2026. Minimum iOS 16.0.
  - Link: **https://apps.apple.com/pl/app/mobywatel/id1339613469**
  - MC's 2025 article says iOS 15. The App Store currently says 16.0.
- **Universal links: none found.** Apple's AASA CDN (the file that would register universal links) returns 404 for all of these domains:
  - `mobywatel.gov.pl`, `www.mobywatel.gov.pl`, `info.mobywatel.gov.pl`, `login.gov.pl`, `www.gov.pl`, `gov.pl`, `moj.gov.pl`
  - For comparison, the same CDN returns files for `pkobp.pl` and `www.amazon.com`, so the method works.
  - On the domains themselves, `/.well-known/apple-app-site-association` returns HTML pages, not AASA files.
- **Custom URL scheme (e.g. `mobywatel://`): NOT CONFIRMED.**
  - No official documentation found.
  - The official app document mentions deep links only for the gov.pl login flow and for opening a separate health app (mojeIKP). It gives no public spec.
- **Conclusion:** there is no documented way to open a specific mObywatel screen, such as "Zastrzeż PESEL". Doddy should:
  - open the **gov.pl / mobywatel.gov.pl https pages** listed below, which work in Safari after login;
  - offer the App Store link to open or install the app;
  - give the in-app path as text instructions.

---

## 10. Other official notes

- **Phone lost with the wallet:**
  - Revoke the mObywatel certificate at **+48 42 253 54 74** (24/7), or activate mObywatel on another phone, which revokes the old one automatically (section 1f).
  - SIM and phone blocking were not researched, per the brief.
- **Foreigners' residence card (karta pobytu):**
  - Report the loss to the voivode who issued it **within 3 days**, and to the police.
  - Apply for a replacement **within 14 days**.
  - Source: https://zielonalinia.gov.pl/zgubiona-karta-pobytu-co-powinien-zrobic-cudzoziemiec/ (09.08.2024)
  - The fee varies by source (50, 100 or 200 zł). **NOT CONFIRMED.**
  - The official MOS page (`mos.cudzoziemcy.gov.pl/informacje/kp/utrata`) was unreachable today (HTTP 503).
- **Signs of identity theft later on** (for example, a loan in your name):
  - Report "nieuprawnione wykorzystanie danych", which cancels the ID and reserves PESEL automatically.
  - Report it to the police.
  - Sources: MC 17.08.2026; the gov.pl identity-theft page (section 1a).

---

## Recommended checklist order (most urgent first)

1. **In danger, or a robbery just happened → 112.** It is for emergencies that need police right now; gov.pl lists theft and robbery among them.
2. **Block bank cards (zastrzeż)** in the bank's app or on its hotline. If you don't know the number, call +48 828 828 828 (24/7, works from abroad, one bank per call). Cards can be used against you immediately, and a permanent block stops all use. A temporary lock only makes sense if the card is probably just mislaid.
3. **Cancel the ID card** in mObywatel, on gov.pl, or at any gmina office. If it was stolen, the police report alone cancels it. Cancellation is immediate even at night, and it automatically reserves PESEL for adults. If you have an e-dowód and expect to find it within days, suspend it instead (max 14 days).
4. **Check that PESEL is reserved** (mObywatel → Usługi → Zastrzeż PESEL), and reserve it if not. It is automatic only for loss reports, so it may be missing if you reported only to the police. It is free and can be lifted at any time.
5. **Block the documents in Dokumenty Zastrzeżone**: mObywatel "Zastrzeż dokument", any bank branch, or 828 828 828. It reaches banks, telecoms and thousands of companies, separately from the state register. gov.pl still recommends it.
6. **Police report if stolen**, unless already done in step 1 or 3. It is needed for the theft itself and also cancels the ID and passport. Bring a passport, driving licence, or use mDowód.
7. **Passport, if it was in the wallet:** report it online, in the app, or at a passport office (abroad: a consulate). Cancellation is immediate and permanent. Abroad, the consul can issue a temporary passport.
8. **Driving licence:** report to the starostwo / city office within 30 days and order a duplicate (100 zł). In Poland you don't need to carry the Polish licence; abroad, carry the physical one.
9. **Apply for a new ID** online or at any gmina. It is free, has a 30-day fingerprint visit if applied online, and takes up to 30 days. You can check readiness online or in the app, and collect it in person.
10. **Follow-ups:** revoke the mObywatel certificate if the phone was lost too. Foreigners: tell the voivode about the residence card within 3 days. Later, check "Kto sprawdzał Twój PESEL" in the app.

---

## URLs for Doddy to open

**Verified today.** "Read" means the page content was read. "Link only" means the URL appears on an official page and returned HTTP 200 today, but the content behind login was not checked.

| # | Purpose | URL | Status |
|---|---|---|---|
| 1 | Cancel ID: info and e-service | https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-swojego-dowodu-osobistego-uniewaznij-dowod | verified today (read) |
| 2 | Cancel ID: e-service target | https://www.mobywatel.gov.pl/twoje-dane/rdo/twoj-dokument | verified today (link only, needs login) |
| 3 | Suspend / un-suspend e-dowód | https://www.gov.pl/web/gov/zglos-zawieszenie-lub-cofnij-zawieszenie-swojego-e-dowodu | verified today (read) |
| 4 | Check whether an ID is cancelled or suspended | https://www.gov.pl/web/gov/Sprawdz-czy-dowod-osobisty-jest-uniewazniony-lub-zawieszony | verified today (read) |
| 5 | Identity theft: cancel ID | https://www.gov.pl/web/gov/zglos-nieuprawnione-wykorzystanie-swoich-danych-osobowych-kradziez-tozsamosci--uniewaznij-dowod | verified today (read) |
| 6 | New ID: info | https://www.gov.pl/web/gov/uzyskaj-dowod-osobisty | verified today (read) |
| 7 | New ID: online form | https://www.mobywatel.gov.pl/form-viewer/?name=wniosek-o-wydanie-dowodu-osobistego | verified today (link only, needs login) |
| 8 | Is the new ID ready? | https://www.gov.pl/web/gov/sprawdz-czy-dowod-osobisty-jest-gotowy | verified today (read) |
| 9 | PESEL reservation: info | https://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel-lub-cofnij-zastrzezenie | verified today (read) |
| 10 | PESEL reservation: e-service | https://www.mobywatel.gov.pl/twoje-dane/rzp-pesel | verified today (link only, needs login) |
| 11 | e-Doręczenia address (needed for online ID cancellation) | https://www.gov.pl/web/gov/uzyskaj-adres-do-e-doreczen-u-publicznego-dostawcy-uslugi-e-doreczen | verified today (link only) |
| 12 | Card-blocking line | `tel:+48828828828` | verified today (zastrzegam.pl) |
| 13 | Card-blocking line: participating banks | https://zastrzegam.pl/uczestnicy/ | verified today (read; list looks out of date) |
| 14 | Dokumenty Zastrzeżone: how to | https://dokumentyzastrzezone.pl/zastrzeganie-dokumentow/ | verified today (read) |
| 15 | Dokumenty Zastrzeżone: banks that accept non-customers | https://dokumentyzastrzezone.pl/lista-bankow-zastrzegajacych-dokumenty/ | verified today (read) |
| 16 | Emergency number | `tel:112` | verified today (gov.pl 112 page) |
| 17 | Report a crime | https://www.gov.pl/web/gov/zglos-przestepstwo | verified today (read) |
| 18 | Driving licence: loss and duplicate | https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-prawa-jazdy | verified today (read) |
| 19 | Driving licence: ePUAP form | https://epuap.gov.pl/wps/portal/strefa-klienta/katalog-spraw/motoryzacja-i-transport/wymiana-prawa-jazdy/wydanie-wtornika-prawa-jazdy | verified today (link only) |
| 20 | Passport: loss | https://www.gov.pl/web/gov/zglos-utrate-lub-zniszczenie-paszportu | verified today (read) |
| 21 | Passport: online form, loss in Poland | https://moj.gov.pl/uslugi/engine/ng/index?xFormsAppName=ZglosUtrateUszkodzenieDokumentuPaszportowego&xFormsOrigin=EXTERNAL&nfc_rodzajZgloszenia=UtrataWKraju | verified today (link only) |
| 22 | Polish consulates worldwide | https://www.gov.pl/web/dyplomacja/polskie-przedstawicielstwa-na-swiecie | verified today (link only) |
| 23 | Passports and temporary passport (MSZ) | https://www.gov.pl/web/dyplomacja/paszporty | verified today (read) |
| 24 | mObywatel in the App Store | https://apps.apple.com/pl/app/mobywatel/id1339613469 | verified today (Apple lookup API) |
| 25 | mObywatel certificate revocation (phone lost) | `tel:+48422535474` | verified today (official app PDF and MC article) |
| 26 | PESEL help line | `tel:+48422535460` | verified today (gov.pl PESEL page) |
| 27 | mObywatel help: PESEL | https://info.mobywatel.gov.pl/uslugi/zastrzez-pesel | **not verified** (site blocked automated access) |
| 28 | mObywatel help: Zastrzeż dokument | https://info.mobywatel.gov.pl/aktualnosci/zastrzez-dokument-w-aplikacji-mobywatel | **not verified** (blocked; content seen only as quoted by ZBP) |
| 29 | Residence card loss (MOS) | https://mos.cudzoziemcy.gov.pl/informacje/kp/utrata | **not verified** (HTTP 503 today) |
| 30 | Any `mobywatel://` deep link | none | **not verified, don't use** |

## Conflicts and gaps to resolve before shipping

1. **In-app wording:** "Załatw sprawę" (MC and the app info PDF, 2025–2026) vs. "Złóż wniosek" (rulebook annex, Sept 2026). Test on a real device before writing exact labels.
2. **mDowód after the ID is cancelled:** the statute suggests it stays valid, but no plain official statement was found (section 1f).
3. **Automatic PESEL reservation after a police-only theft report:** not stated plainly (section 2).
4. **"Zastrzeż dokument" in the app:** whether it covers the driving licence. Sources disagree (section 4).
5. **The 828 participant list** looks out of date (section 3).
6. **Push notification when the new ID is ready:** not confirmed.
7. **No national online police report form** found.
8. **mPrawo Jazdy abroad** is not confirmed. Driving while waiting for a duplicate licence is not confirmed.
9. **mObywatel deep links:** no universal links are registered and no URL scheme is documented. Use https pages and the App Store link.
10. **Doddy's copy** must never say "your ID is cancelled", "PESEL reserved" or "card blocked". Doddy only opens links. Those outcomes are confirmed by the app, gov.pl or the bank, and the person must check them there.
