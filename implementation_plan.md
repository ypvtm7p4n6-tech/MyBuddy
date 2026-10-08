# Implementatieplan — MyBuddy (financiën-app voor iPhone, iPad en Mac)

Status: **wacht op akkoord**. Er is nog geen code geschreven.

## 1. Uitgangspunten

| Onderdeel | Keuze |
|---|---|
| Platformen | iPhone, iPad, Mac vanuit één SwiftUI-codebase (multiplatform target) |
| Designtaal | Liquid Glass (iOS/iPadOS/macOS 26): `glassEffect`, `GlassEffectContainer`, glass-knoppen, drijvende glazen tabbalk. Op OS 18/15 valt het terug op `Material`. |
| Vormgeving | Eén `Theme`: vaste hoekradii (kaart 28 → binnenelement 16 → chip 10; binnenradius = buitenradius − padding), één kleurpalet, MeshGradient-achtergrond (groen, naar voorbeeld EveryDollar) |
| Opslag | Lokaal JSON-bestand (Codable, atomisch schrijven). Geen account, geen server. iCloud-sync is een latere stap. |
| Taal / valuta | Nederlands, euro (`nl_NL`) |
| Rekenlogica | Aparte Swift package `MyBuddyCore` (alleen Foundation) zodat alle berekeningen unit-testbaar zijn. De app bevat alleen UI + `AppStore`. |
| Projectbestand | `project.yml` (XcodeGen) + README met 3 stappen. Een `.xcodeproj` met de hand schrijven zonder Xcode is te foutgevoelig. |

## 2. Schermen en koppelingen

**Navigatie**: `TabView` (iPhone: glazen tabbalk onderaan, iPad/Mac: zijbalk) met 3 tabs: **Home**, **Geld**, **Beleggen**. Eén `Router` bepaalt tab + diepe link, zodat elk blok op elke pagina naar de juiste plek springt.

### Tab 1 — Home
- Bovenaan: **Nog te verdelen deze maand** (inkomen − uitgaven − potten − inleg). Tik → Geld, sectie "Verdelen".
- Blok 1 **Overzicht**: gestapelde staafgrafiek per maand (uitgaven / gespaard / belegd / over), totaal vermogen. Tik → Geld, overzicht (maand/half jaar/jaar).
- Blok 2 **Spaarpotten**: 3 mini-blokken met doel + saldo + voortgangsring. Je kiest zelf welke 3 (keuzeknop). Tik op een pot → detail van die pot; tik op de kop → Geld, potten.
- Blok 3 **Beleggingen**: groeigrafiek (historie + prognose) en daaronder tegels per beleggingssoort met bedrag (zelf te kiezen welke). Tik → Beleggen.

### Tab 2 — Geld (spaarpotten + bankrekening)
- Periodekeuze bovenaan: **Maand / Half jaar / Jaar**, met terug/vooruit. Toekomstige periodes zijn "Verwacht" (gebaseerd op standaardinstellingen) en visueel gemarkeerd.
- Totaalbeeld voor de gekozen periode: inkomen, uitgaven, gespaard, belegd, over, gemiddelde per maand, grafiek per maand, vermogen aan het eind.
- **Salaris**: menu met vast bedrag per maand óf uurloon × uren per week (× 52 / 12). Per maand overschrijfbaar (bedrag of werkelijk aantal uren).
- **Overige inkomsten** deze maand (naam + bedrag, optioneel terugkerend).
- **Uitgaven** deze maand (naam + bedrag, optioneel terugkerend, bv. huur).
- **Verdelen**: per spaarpot en per belegging een bedrag voor deze maand; live "nog te verdelen"; snelkeuzes (standaard toepassen, rest gelijk verdelen, alles op nul).
- **Spaarpotten**: lijst + toevoegen. **Pot-detail**: doel aanpassen, saldo aanpassen, geld storten/opnemen/overboeken, geschiedenis ("waar is het heen gegaan"), geschatte datum waarop het doel gehaald wordt, verwijderen.
- **Bankrekening**: startsaldo (invulbaar) + geschat saldo = startsaldo + overschot van alle maanden t/m nu.

### Tab 3 — Beleggen
- Samenvatting: waarde, ingelegd, rendement, grafiek (historie + prognose).
- **Mijn beleggingen**: toevoegen/wijzigen (naam, soort, verwacht rendement, kosten, maandelijkse inleg), waarde bijwerken (geeft meetpunt voor de grafiek).
- **Toekomstschatting**: horizon in dagen / weken / maanden / jaren, drie scenario's (voorzichtig / verwacht / optimistisch), optioneel "in koopkracht van vandaag" (inflatie), uitsplitsing eigen inleg vs. rendement.
- **Doelen** (pensioen, vakantie, parttime werken, eigen doel): benodigd kapitaal, voortgang, **hoe lang duurt het**, welke maandinleg is nodig om uiterlijk op een gekozen datum klaar te zijn.
- **Versnellers** per doel: extra inleg (+50/+100/+250), vrije ruimte van deze maand inzetten, +1 %-punt rendement, 0,5 %-punt lagere kosten, eenmalige storting, inleg jaarlijks verhogen, doelbedrag 10 % lager. Per versneller "x maanden eerder"; meerdere tegelijk aanzetten en vergelijken in een grafiek (basis vs. combinatie).

### Koppelingen (klik-routes)
| Van | Naar |
|---|---|
| Home › Nog te verdelen | Geld › Verdelen |
| Home › Overzicht | Geld › Totaalbeeld |
| Home › Spaarpot-blok | Geld › Pot-detail |
| Home › Kop "Spaarpotten" | Geld › Potten |
| Home › Beleggingen | Beleggen |
| Geld › Verdelen › beleggingsrij | Beleggen › Belegging-detail |
| Beleggen › Versneller "vrije ruimte" | leest "nog te verdelen" uit Geld |

## 3. Rekenmodel (alle regels in `MyBuddyCore`)
- Bedragen als `Double`, afgerond op centen bij invoer en bij sommen.
- Maand = `YearMonth`. Een maandplan (salaris-override, extra inkomsten, uitgaven, verdeling) wordt opgeslagen zodra de maand ≤ nu is of wordt bewerkt; toekomstige maanden worden on-the-fly afgeleid uit standaarden (terugkerende regels, standaardinleg per pot).
- Pot-saldo = handmatige boekingen + som van maandverdelingen vanaf de startmaand t/m de gevraagde maand. Saldo aanpassen maakt een correctieboeking.
- Waarde belegging = laatste meetpunt + inleg in latere maanden; toekomst = groei met `(1 + r − kosten)^(1/12) − 1` per maand + geplande inleg.
- Toekomstwaarde, looptijd tot doel, benodigde inleg: maandelijkse samengestelde rente, inleg einde maand, speciale tak voor 0 % rendement, maximum 100 jaar.
- Benodigd kapitaal: pensioen = (uitgaven − AOW/pensioen) × 12 / opnamepercentage (standaard 4 %); parttime = inkomensgat × 12 / opnamepercentage, of lijfrente over N jaar; vakantie/eigen doel = vast bedrag. Optioneel in koopkracht van vandaag (reëel rendement = (1+r)/(1+inflatie) − 1).

## 4. Bestanden

```
[NEW] project.yml                                  XcodeGen: multiplatform app (iOS+macOS), verwijst naar package
[NEW] README.md                                    Bouwen in 3 stappen, overzicht, bekende beperkingen
[NEW] system_architecture.md                       Ontwerpkeuzes voor vervolgwerk
[NEW] .gitignore
[NEW] Packages/MyBuddyCore/Package.swift
[NEW] Packages/MyBuddyCore/Sources/MyBuddyCore/
        YearMonth.swift          Maand-type, optellen, sleutel
        Models.swift             SalarySettings, MoneyLine, MonthPlan, Pot, PotEntry, Holding, LifeGoal, FinanceData
        FinanceData+Plan.swift   Maandplan afleiden/materialiseren, inkomen, uitgaven, samenvattingen, periodes
        FinanceData+Pots.swift   Saldo's, boekingen, overboeken, doelprognose pot
        FinanceData+Invest.swift Waarde/inleg per maand, historie + prognose, portefeuille-reeks
        Projection.swift         Toekomstwaarde, looptijd, benodigde inleg, scenario's, horizon-eenheden
        GoalEngine.swift         Doelen, benodigd kapitaal, versnellers, gecombineerd scenario
        Persistence.swift        JSON laden/opslaan, voorbeelddata
[NEW] Packages/MyBuddyCore/Tests/MyBuddyCoreTests/  YearMonth, Plan, Pots, Invest, Projection, GoalEngine
[NEW] App/
        MyBuddyApp.swift, AppStore.swift, Router.swift
        Theme/       Theme.swift (kleuren, radii), GlassStyle.swift (glass + fallback), Formatters.swift
        Components/  GlassCard, SectionHeader, ProgressRing, CurrencyField, MoneyText, EmptyState, IconPicker
        Home/        HomeView, OverviewBlock, PotsBlock, InvestmentsBlock, PotPickerSheet, HoldingPickerSheet
        Money/       MoneyView, PeriodPicker, PeriodSummaryCard, SalaryCard + SalarySheet, IncomeCard, ExpensesCard,
                     DistributeCard, PotsList, PotDetailView, PotEditSheet, PotEntrySheet, BankCard
        Invest/      InvestView, HoldingDetailView, HoldingEditSheet, ValueUpdateSheet, ProjectionCard,
                     GoalsSection, GoalDetailView (versnellers), GoalEditSheet
        Settings/    SettingsView (inflatie, opnamepercentage, voorbeelddata, alles wissen)
        Assets.xcassets (AccentColor, AppIcon-placeholder)
```

## 5. Volgorde van uitvoeren
1. `MyBuddyCore` + tests (rekenlogica eerst, want de UI leunt hierop).
2. `Theme` + componenten, `AppStore`, `Router`, app-skelet met 3 tabs.
3. Geld-tab, dan Home, dan Beleggen-tab.
4. Instellingen, voorbeelddata, README, `system_architecture.md`.
5. Verificatie (zie hieronder), commit en push naar `claude/finance-tracking-apple-app-otul5v`.

## 6. Verificatie — wat ik wel en niet kan
- In deze omgeving staat **geen Swift-compiler en geen Xcode**; `download.swift.org` is geblokkeerd. Ik kan de app dus hier **niet bouwen of draaien**.
- Wat ik wel doe: syntaxcontrole van alle Swift-bestanden met een parser, de verwachte testwaarden onafhankelijk narekenen (Python), en elke API die ik gebruik beperken tot bekende SwiftUI/Charts-API's.
- Wat jij dan doet: `xcodegen` + bouwen in Xcode 26, en `swift test` in `Packages/MyBuddyCore`. Meld je eventuele compilerfouten, dan verwerk ik die direct. Reken op een of twee van zulke rondes.

## 7. Aannames (zeg het als je het anders wilt)
1. Alle schermen NL; bedragen in euro.
2. "Bankrekening" is een geschat saldo uit startsaldo + overschot, geen bankkoppeling (geen PSD2/Open Banking).
3. Beleggingswaarden vul je zelf in (geen koersen ophalen); de app rekent ertussen door met verwacht rendement.
4. Home-blok "Overzicht" gaat naar het totaalbeeld in tab Geld (daar zit de maand/half jaar/jaar-keuze).
5. Uitgaven zijn toegevoegd (niet expliciet gevraagd) omdat "nog te verdelen" anders niet klopt.
