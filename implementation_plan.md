# Implementatieplan v2 — MyBuddy (iPhone, iPad, Mac)

Verwerkt je feedback: donker olijfgroen, saldo bankrekening zelf invullen en doorrekenen, live koersen, drie tabs onderin met per blok een eigen pagina, doelen/versnellers op basis van jouw gegevens.

## 1. Uitgangspunten
| Onderdeel | Keuze |
|---|---|
| Platformen | Eén SwiftUI-codebase voor iPhone, iPad, Mac (XcodeGen-project, Xcode 26) |
| Designtaal | Liquid Glass (`glassEffect`), terugval op `Material` onder iOS 26 / macOS 26 |
| Kleur | Donker olijfgroen (`#556B2F` basis, dieper `#2B3418`, lichter `#A8BE6A`), MeshGradient-achtergrond, lichte en donkere modus |
| Vorm | Vaste radii (kaart 30 → tegel 16 → chip 10, binnen = buiten − inset), overal dezelfde `BlockCard` |
| Tabbalk | Eigen zwevende glazen balk **onderin** op iPhone, iPad én Mac: **Home · Savings · Beleggingen** |
| Opslag | Lokaal JSON (Codable, atomisch, corrupte file wordt apart bewaard) |
| Koersen | Yahoo Finance (onofficieel, geen sleutel): zoeken, koers, historie, wisselkoers naar euro. Achter een `QuoteService`-protocol zodat je later van bron wisselt. |
| Logica | `App/Core` (alleen Foundation, geen SwiftUI). Een SwiftPM-testpakket in `CoreTests/` gebruikt dezelfde bestanden via symlink, dus `swift test` werkt zonder Xcode. |

## 2. Navigatie: elk blok heeft een eigen pagina
Drie tabs onderin. Elke tab is een pagina met glazen blokken in dezelfde stijl. **Elk blok opent een eigen detailpagina; die is alleen via dat blok te bereiken** (niet via de tabbalk).

### Home
| Blok | Toont | Opent |
|---|---|---|
| Nog te verdelen | bedrag deze maand | Verdelen |
| Overzicht | grafiek per maand (uitgaven/gespaard/belegd/over) + vermogen | Overzicht (alles bij elkaar, maand / half jaar / jaar) |
| Spaarpotten | 3 zelf gekozen potten (doel + saldo) | kop: Alle spaarpotten; pot: Pot-detail |
| Beleggingen | groeigrafiek + tegels per zelf gekozen belegging | kop: Portefeuille; tegel: Belegging-detail |

### Savings
| Blok | Toont | Opent |
|---|---|---|
| Periode (maand / half jaar / jaar, terug en vooruit) | totalen + grafiek | Overzicht |
| Salaris & inkomsten | salaris (vast of uurloon × uren) + overige inkomsten | Salaris & inkomsten bewerken |
| Uitgaven | totaal, grootste posten | Uitgaven bewerken |
| Verdelen | nog te verdelen + voortgangsbalk | Verdelen per pot en belegging |
| Spaarpotten | totaal gespaard | Alle spaarpotten → Pot-detail (doel, saldo, storten/opnemen/overboeken, geschiedenis) |
| Bankrekening | zelf ingevuld saldo + verwacht verloop | Bankrekening (saldo invullen, geschiedenis, buffer) |

### Beleggingen
| Blok | Toont | Opent |
|---|---|---|
| Portefeuille | waarde, rendement, mini-grafiek | Portefeuille (koersen verversen, beleggingen beheren) → Belegging-detail |
| Toekomstschatting | verwachte waarde over x | Rekenmachine: dagen/weken/maanden/jaren, 3 scenario's, inflatie, streefbedrag |
| Doelen | voortgang van je doelen | Doelen → Doel-detail (pensioen, vakantie, parttime, eigen doel) |
| Versnellers | beste versneller nu | Versnellers per doel, meerdere combineren |

## 3. Rekenmodel
- Maandplan per maand: salaris-override, extra inkomsten, uitgaven, verdeling. Maanden ≤ nu worden vastgelegd; toekomst wordt afgeleid uit standaarden (terugkerende regels, standaardinleg).
- **Nog te verdelen** = inkomen − uitgaven − potten − inleg beleggingen.
- **Pot-saldo** = handmatige boekingen + maandverdelingen vanaf startmaand.
- **Bankrekening**: jij vult het saldo in (elke invoer wordt bewaard). Verwacht saldo = laatste invoer + overschot van latere maanden. Telt mee in vermogen en in versnellers (overtollig saldo boven buffer).
- **Beleggingen**: waarde = aantal × live koers (euro), of handmatig ingevulde waarde. Elke verversing bewaart een meetpunt, zo ontstaat de groeigrafiek. Toekomst = maandelijkse groei met rendement − kosten + geplande inleg.
- **Doelen**: benodigd kapitaal (pensioen: (uitgaven − AOW) × 12 / opnamepercentage; parttime: inkomensgat uit je salaris; vakantie/eigen: vast bedrag), looptijd via maandelijkse simulatie, optioneel in koopkracht van vandaag.
- **Versnellers uit jouw gegevens** (alleen getoond als ze op jouw situatie van toepassing zijn, gesorteerd op winst in maanden): vrije ruimte inzetten, 5 % van inkomen extra, grootste uitgaven 10 % omlaag, overtollig bankgeld, potten boven doel, hoge beleggingskosten omlaag, herverdelen naar hoger rendement, uren extra (bij uurloon), inleg jaarlijks verhogen, doel 10 % lager.

## 4. Bestanden
```
[NEW] project.yml  README.md  system_architecture.md  task.md  .gitignore
[NEW] CoreTests/Package.swift, Sources/MyBuddyCore → symlink naar ../App/Core, Tests/MyBuddyCoreTests/*
[NEW] App/Core/   YearMonth, Models, Plan, Pots, Bank, Invest, Growth, Goals, Accelerators, Quotes, Formatting, Persistence, SampleData
[NEW] App/        MyBuddyApp, AppStore, Router, RootView, Theme, Glass, Components, Forms
[NEW] App/Pages/  Home*, Savings*, Invest*, detailpagina's, sheets, Settings
[NEW] App/Assets.xcassets (AppIcon, AccentColor)
```

## 5. Verificatie en beperkingen
- Deze omgeving heeft **geen Swift-compiler en geen Xcode** (`download.swift.org` geblokkeerd) en **geen toegang tot Yahoo**. Ik kan niet bouwen, testen of koersen ophalen.
- Wel gedaan: syntaxcontrole met een Swift-parser, testwaarden onafhankelijk narekenen in Python, parser-tests voor de koersdata op voorbeeld-JSON.
- Daarna jij: `xcodegen`, bouwen in Xcode 26, `swift test` in `CoreTests/`. Compilerfouten stuur je door, dan los ik ze op.
