import Foundation

// De uitvoer van de coderingen van HEAD (b944e43, voor de startdatum) voor `startFixtureLegacyData()` (StartDateFixtures.swift),
// zoals die vlak voor de bouw van golf 1 is vastgelegd met de toenmalige `FinanceStorage.makeEncoder()` en `makeFileEncoder()`.
// `StartDateModelTests` vergelijkt de huidige coderingen er byte voor byte mee: zonder startdatum mag er niets veranderd zijn.
// Pas deze tekst nooit aan om een test te laten slagen: dan is het opslagformaat veranderd.
enum StartDateLegacyOutput {
    /// `FinanceStorage.makeEncoder()`: opgemaakt met vaste volgorde van sleutels (cloud, back-up, vergelijken).
    static let pretty = """
{
  "appliedAccelerators" : [
    {
      "acceleratorID" : "savings-rate",
      "before" : {
        "goals" : [

        ],
        "holdings" : [

        ],
        "newPlanKeys" : [

        ],
        "plans" : {

        },
        "pots" : [

        ]
      },
      "date" : "2026-02-20T12:00:00Z",
      "goalID" : "5AD7E000-0000-4000-8000-000000000061",
      "id" : "5AD7E000-0000-4000-8000-000000000071",
      "summary" : [
        "Rente van 1% naar 2%"
      ],
      "title" : "Hogere spaarrente"
    }
  ],
  "bankEntries" : [
    {
      "amount" : -50,
      "date" : "2026-01-13T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000051",
      "kind" : "toPot",
      "note" : "Naar Buffer",
      "pairID" : "5AD7E000-0000-4000-8000-000000000023",
      "potID" : "5AD7E000-0000-4000-8000-000000000001"
    },
    {
      "amount" : 80,
      "date" : "2026-01-16T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000052",
      "kind" : "deposit",
      "note" : ""
    }
  ],
  "bankSnapshots" : [
    {
      "balance" : 1850.25,
      "date" : "2026-01-03T12:30:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000041",
      "note" : "Begin"
    },
    {
      "balance" : -12.5,
      "date" : "2026-02-10T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000042",
      "note" : ""
    }
  ],
  "goals" : [
    {
      "funding" : {
        "pot" : {
          "_0" : "5AD7E000-0000-4000-8000-000000000001"
        }
      },
      "hoursFrom" : 0,
      "hoursTo" : 0,
      "id" : "5AD7E000-0000-4000-8000-000000000061",
      "inflationAdjusted" : true,
      "kind" : "vacation",
      "monthlySpending" : 0,
      "name" : "Vakantie Japan",
      "otherMonthlyIncome" : 0,
      "targetAmount" : 3500,
      "targetDate" : "2026-10-28T12:00:00Z",
      "withdrawalRate" : 0.04
    }
  ],
  "holdings" : [
    {
      "annualCost" : 0.002,
      "contributionMode" : "percentage",
      "contributionPercent" : 10,
      "expectedReturn" : 0.06,
      "id" : "5AD7E000-0000-4000-8000-000000000003",
      "investedTotal" : 1250,
      "kind" : "etf",
      "lastPrice" : 104.4,
      "lastPriceDate" : "2026-01-31T12:00:00Z",
      "monthlyContribution" : 75,
      "name" : "Wereldfonds",
      "priceCurrency" : "EUR",
      "snapshots" : [
        {
          "date" : "2026-01-21T12:00:00Z",
          "id" : "5AD7E000-0000-4000-8000-000000000031",
          "invested" : 1250,
          "value" : 1300
        }
      ],
      "startMonth" : "2026-09",
      "ticker" : "VWCE.DE",
      "transferDay" : 5,
      "units" : 12.5
    }
  ],
  "homeHoldingIDs" : [
    "5AD7E000-0000-4000-8000-000000000003"
  ],
  "homePotIDs" : [
    "5AD7E000-0000-4000-8000-000000000002",
    "5AD7E000-0000-4000-8000-000000000001"
  ],
  "modifiedAt" : "2026-03-02T15:15:00Z",
  "months" : {
    "2026-09" : {
      "allocations" : {
        "5AD7E000-0000-4000-8000-000000000001" : 150,
        "5AD7E000-0000-4000-8000-000000000003" : 75
      },
      "endedSeries" : [
        "5AD7E000-0000-4000-8000-000000000018"
      ],
      "expenses" : [
        {
          "amount" : 900,
          "day" : 1,
          "id" : "5AD7E000-0000-4000-8000-000000000013",
          "isRecurring" : true,
          "kind" : "fixed",
          "name" : "Huur",
          "potShares" : [

          ],
          "seriesID" : "5AD7E000-0000-4000-8000-000000000014"
        },
        {
          "amount" : 100,
          "id" : "5AD7E000-0000-4000-8000-000000000015",
          "isException" : true,
          "isRecurring" : false,
          "kind" : "variable",
          "name" : "Tandarts",
          "potShares" : [
            {
              "amount" : 40,
              "id" : "5AD7E000-0000-4000-8000-000000000016",
              "potID" : "5AD7E000-0000-4000-8000-000000000001"
            }
          ]
        }
      ],
      "extraIncome" : [
        {
          "amount" : 120,
          "day" : 20,
          "id" : "5AD7E000-0000-4000-8000-000000000011",
          "isRecurring" : true,
          "kind" : "fixed",
          "name" : "Zorgtoeslag",
          "potShares" : [

          ],
          "seriesID" : "5AD7E000-0000-4000-8000-000000000012"
        }
      ],
      "percentAllocations" : {
        "5AD7E000-0000-4000-8000-000000000002" : {
          "basis" : "allIncome",
          "percent" : 3.5
        }
      },
      "skippedSeries" : [
        "5AD7E000-0000-4000-8000-000000000017"
      ],
      "transferDay" : 3
    },
    "2026-10" : {
      "allocations" : {

      },
      "expenses" : [

      ],
      "extraIncome" : [

      ],
      "hoursOverride" : 120.5,
      "salaryOverride" : 2000
    }
  },
  "potEntries" : [
    {
      "amount" : 500,
      "date" : "2026-01-02T13:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000021",
      "kind" : "opening",
      "note" : "",
      "potID" : "5AD7E000-0000-4000-8000-000000000001"
    },
    {
      "amount" : 50,
      "date" : "2026-01-13T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000022",
      "kind" : "deposit",
      "note" : "Van bankrekening",
      "pairID" : "5AD7E000-0000-4000-8000-000000000023",
      "potID" : "5AD7E000-0000-4000-8000-000000000001"
    },
    {
      "amount" : 2.5,
      "date" : "2026-04-01T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000024",
      "kind" : "interest",
      "note" : "Rente 2% per jaar",
      "potID" : "5AD7E000-0000-4000-8000-000000000001"
    }
  ],
  "pots" : [
    {
      "colorIndex" : 1,
      "createdAt" : "2026-01-02T12:00:00Z",
      "goalAmount" : 5000,
      "goalDate" : "2027-02-05T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000001",
      "interestPayout" : "quarterly",
      "interestPayoutDay" : 28,
      "interestPayoutMonth" : 3,
      "interestRate" : 0.02,
      "monthlyContribution" : 150,
      "name" : "Buffer",
      "startMonth" : "2026-09",
      "symbol" : "shield.lefthalf.filled",
      "transferDay" : 3
    },
    {
      "colorIndex" : 3,
      "contributionBasis" : "allIncome",
      "contributionMode" : "percentage",
      "contributionPercent" : 3.5,
      "createdAt" : "2026-01-03T12:00:00Z",
      "id" : "5AD7E000-0000-4000-8000-000000000002",
      "interestPayout" : "yearly",
      "interestPayoutDay" : 1,
      "interestPayoutMonth" : 1,
      "interestRate" : 0,
      "monthlyContribution" : 100,
      "name" : "Vakantie",
      "startMonth" : "2026-10",
      "symbol" : "airplane"
    }
  ],
  "salary" : {
    "anchor" : "2026-09-11",
    "fixedMonthly" : 0,
    "hourlyRate" : 14.35,
    "hoursPerWeek" : 32,
    "interval" : 4,
    "mode" : "hourly",
    "payDay" : 25,
    "schedule" : "weeks"
  },
  "settings" : {
    "autoRefreshPrices" : true,
    "bankBufferMonths" : 3,
    "blockOrder" : {
      "overview" : [
        "upcoming",
        "pots"
      ]
    },
    "defaultWithdrawalRate" : 0.04,
    "inflation" : 0.025,
    "savingsRate" : 0.02
  },
  "startMonth" : "2026-09",
  "version" : 1
}
"""

    /// `FinanceStorage.makeFileEncoder()`: compact met vaste volgorde van sleutels (het lokale bestand).
    static let compact = """
{"appliedAccelerators":[{"acceleratorID":"savings-rate","before":{"goals":[],"holdings":[],"newPlanKeys":[],"plans":{},"pots":[]},"date":"2026-02-20T12:00:00Z","goalID":"5AD7E000-0000-4000-8000-000000000061","id":"5AD7E000-0000-4000-8000-000000000071","summary":["Rente van 1% naar 2%"],"title":"Hogere spaarrente"}],"bankEntries":[{"amount":-50,"date":"2026-01-13T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000051","kind":"toPot","note":"Naar Buffer","pairID":"5AD7E000-0000-4000-8000-000000000023","potID":"5AD7E000-0000-4000-8000-000000000001"},{"amount":80,"date":"2026-01-16T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000052","kind":"deposit","note":""}],"bankSnapshots":[{"balance":1850.25,"date":"2026-01-03T12:30:00Z","id":"5AD7E000-0000-4000-8000-000000000041","note":"Begin"},{"balance":-12.5,"date":"2026-02-10T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000042","note":""}],"goals":[{"funding":{"pot":{"_0":"5AD7E000-0000-4000-8000-000000000001"}},"hoursFrom":0,"hoursTo":0,"id":"5AD7E000-0000-4000-8000-000000000061","inflationAdjusted":true,"kind":"vacation","monthlySpending":0,"name":"Vakantie Japan","otherMonthlyIncome":0,"targetAmount":3500,"targetDate":"2026-10-28T12:00:00Z","withdrawalRate":0.04}],"holdings":[{"annualCost":0.002,"contributionMode":"percentage","contributionPercent":10,"expectedReturn":0.06,"id":"5AD7E000-0000-4000-8000-000000000003","investedTotal":1250,"kind":"etf","lastPrice":104.4,"lastPriceDate":"2026-01-31T12:00:00Z","monthlyContribution":75,"name":"Wereldfonds","priceCurrency":"EUR","snapshots":[{"date":"2026-01-21T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000031","invested":1250,"value":1300}],"startMonth":"2026-09","ticker":"VWCE.DE","transferDay":5,"units":12.5}],"homeHoldingIDs":["5AD7E000-0000-4000-8000-000000000003"],"homePotIDs":["5AD7E000-0000-4000-8000-000000000002","5AD7E000-0000-4000-8000-000000000001"],"modifiedAt":"2026-03-02T15:15:00Z","months":{"2026-09":{"allocations":{"5AD7E000-0000-4000-8000-000000000001":150,"5AD7E000-0000-4000-8000-000000000003":75},"endedSeries":["5AD7E000-0000-4000-8000-000000000018"],"expenses":[{"amount":900,"day":1,"id":"5AD7E000-0000-4000-8000-000000000013","isRecurring":true,"kind":"fixed","name":"Huur","potShares":[],"seriesID":"5AD7E000-0000-4000-8000-000000000014"},{"amount":100,"id":"5AD7E000-0000-4000-8000-000000000015","isException":true,"isRecurring":false,"kind":"variable","name":"Tandarts","potShares":[{"amount":40,"id":"5AD7E000-0000-4000-8000-000000000016","potID":"5AD7E000-0000-4000-8000-000000000001"}]}],"extraIncome":[{"amount":120,"day":20,"id":"5AD7E000-0000-4000-8000-000000000011","isRecurring":true,"kind":"fixed","name":"Zorgtoeslag","potShares":[],"seriesID":"5AD7E000-0000-4000-8000-000000000012"}],"percentAllocations":{"5AD7E000-0000-4000-8000-000000000002":{"basis":"allIncome","percent":3.5}},"skippedSeries":["5AD7E000-0000-4000-8000-000000000017"],"transferDay":3},"2026-10":{"allocations":{},"expenses":[],"extraIncome":[],"hoursOverride":120.5,"salaryOverride":2000}},"potEntries":[{"amount":500,"date":"2026-01-02T13:00:00Z","id":"5AD7E000-0000-4000-8000-000000000021","kind":"opening","note":"","potID":"5AD7E000-0000-4000-8000-000000000001"},{"amount":50,"date":"2026-01-13T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000022","kind":"deposit","note":"Van bankrekening","pairID":"5AD7E000-0000-4000-8000-000000000023","potID":"5AD7E000-0000-4000-8000-000000000001"},{"amount":2.5,"date":"2026-04-01T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000024","kind":"interest","note":"Rente 2% per jaar","potID":"5AD7E000-0000-4000-8000-000000000001"}],"pots":[{"colorIndex":1,"createdAt":"2026-01-02T12:00:00Z","goalAmount":5000,"goalDate":"2027-02-05T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000001","interestPayout":"quarterly","interestPayoutDay":28,"interestPayoutMonth":3,"interestRate":0.02,"monthlyContribution":150,"name":"Buffer","startMonth":"2026-09","symbol":"shield.lefthalf.filled","transferDay":3},{"colorIndex":3,"contributionBasis":"allIncome","contributionMode":"percentage","contributionPercent":3.5,"createdAt":"2026-01-03T12:00:00Z","id":"5AD7E000-0000-4000-8000-000000000002","interestPayout":"yearly","interestPayoutDay":1,"interestPayoutMonth":1,"interestRate":0,"monthlyContribution":100,"name":"Vakantie","startMonth":"2026-10","symbol":"airplane"}],"salary":{"anchor":"2026-09-11","fixedMonthly":0,"hourlyRate":14.35,"hoursPerWeek":32,"interval":4,"mode":"hourly","payDay":25,"schedule":"weeks"},"settings":{"autoRefreshPrices":true,"bankBufferMonths":3,"blockOrder":{"overview":["upcoming","pots"]},"defaultWithdrawalRate":0.04,"inflation":0.025,"savingsRate":0.02},"startMonth":"2026-09","version":1}
"""
}
