import Foundation

// De uitvoer van de coderingen van HEAD (0333505, golf 1 van docs/work/plan.md klaar, voor de ronde van docs/work/plan2.md) voor
// `verdelenFixtureLegacyData()` (VerdelenFixtures.swift), zoals die vlak voor de bouw van D1 t/m D5 is vastgelegd met de toenmalige
// `FinanceStorage.makeEncoder()` en `makeFileEncoder()`. `DistributionPersistenceTests` vergelijkt de huidige coderingen er byte voor
// byte mee: zonder extra bedrag, extra overschrijfdata, bankrij of doel met meer potten mag er niets veranderd zijn.
// Pas deze tekst nooit aan om een test te laten slagen: dan is het opslagformaat veranderd.
enum VerdelenLegacyOutput {
    /// `FinanceStorage.makeEncoder()`: opgemaakt met vaste volgorde van sleutels (cloud, back-up, vergelijken).
    static let pretty = """
{
  "appliedAccelerators" : [

  ],
  "bankEntries" : [
    {
      "amount" : 60,
      "date" : "2026-03-17T12:00:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000051",
      "kind" : "deposit",
      "note" : "Verjaardag"
    }
  ],
  "bankSnapshots" : [
    {
      "balance" : 2150.5,
      "date" : "2026-03-12T12:30:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000041",
      "note" : "Begin"
    }
  ],
  "goals" : [
    {
      "funding" : {
        "pot" : {
          "_0" : "7E4D0000-0000-4000-8000-000000000002"
        }
      },
      "hoursFrom" : 0,
      "hoursTo" : 0,
      "id" : "7E4D0000-0000-4000-8000-000000000061",
      "inflationAdjusted" : true,
      "kind" : "vacation",
      "monthlySpending" : 0,
      "name" : "Vakantie Japan",
      "otherMonthlyIncome" : 0,
      "targetAmount" : 3500,
      "targetDate" : "2026-10-28T12:00:00Z",
      "withdrawalRate" : 0.04
    },
    {
      "funding" : {
        "custom" : {
          "annualReturn" : 0.03,
          "monthly" : 150,
          "start" : 500
        }
      },
      "hoursFrom" : 0,
      "hoursTo" : 0,
      "id" : "7E4D0000-0000-4000-8000-000000000062",
      "inflationAdjusted" : true,
      "kind" : "custom",
      "monthlySpending" : 0,
      "name" : "Camper",
      "otherMonthlyIncome" : 0,
      "targetAmount" : 12000,
      "withdrawalRate" : 0.04
    },
    {
      "funding" : {
        "portfolio" : {

        }
      },
      "hoursFrom" : 0,
      "hoursTo" : 0,
      "id" : "7E4D0000-0000-4000-8000-000000000063",
      "inflationAdjusted" : true,
      "kind" : "retirement",
      "monthlySpending" : 0,
      "name" : "Pensioen",
      "otherMonthlyIncome" : 0,
      "targetAmount" : 0,
      "withdrawalRate" : 0.04
    }
  ],
  "holdings" : [
    {
      "annualCost" : 0.002,
      "contributionMode" : "percentage",
      "contributionPercent" : 8,
      "expectedReturn" : 0.06,
      "id" : "7E4D0000-0000-4000-8000-000000000004",
      "investedTotal" : 900,
      "kind" : "etf",
      "lastPrice" : 119,
      "lastPriceDate" : "2026-02-01T12:00:00Z",
      "monthlyContribution" : 60,
      "name" : "Wereldfonds",
      "priceCurrency" : "EUR",
      "snapshots" : [
        {
          "date" : "2026-01-31T12:00:00Z",
          "id" : "7E4D0000-0000-4000-8000-000000000031",
          "invested" : 900,
          "value" : 950
        }
      ],
      "startMonth" : "2026-03",
      "ticker" : "VWCE.DE",
      "transferDay" : 12,
      "units" : 8
    },
    {
      "annualCost" : 0.001,
      "expectedReturn" : 0.03,
      "id" : "7E4D0000-0000-4000-8000-000000000005",
      "investedTotal" : 0,
      "kind" : "etf",
      "monthlyContribution" : 40,
      "name" : "Obligaties",
      "snapshots" : [

      ],
      "startMonth" : "2026-03",
      "units" : 0
    }
  ],
  "homeHoldingIDs" : [
    "7E4D0000-0000-4000-8000-000000000004"
  ],
  "homePotIDs" : [
    "7E4D0000-0000-4000-8000-000000000002",
    "7E4D0000-0000-4000-8000-000000000001"
  ],
  "modifiedAt" : "2026-04-01T15:15:00Z",
  "months" : {
    "2026-03" : {
      "allocations" : {
        "7E4D0000-0000-4000-8000-000000000001" : 200,
        "7E4D0000-0000-4000-8000-000000000005" : 40
      },
      "expenses" : [
        {
          "amount" : 950,
          "day" : 1,
          "id" : "7E4D0000-0000-4000-8000-000000000013",
          "isRecurring" : true,
          "kind" : "fixed",
          "name" : "Huur",
          "potShares" : [

          ],
          "seriesID" : "7E4D0000-0000-4000-8000-000000000014"
        },
        {
          "amount" : 120,
          "day" : 15,
          "id" : "7E4D0000-0000-4000-8000-000000000015",
          "isRecurring" : false,
          "kind" : "variable",
          "name" : "Fiets",
          "potShares" : [
            {
              "amount" : 50,
              "id" : "7E4D0000-0000-4000-8000-000000000016",
              "potID" : "7E4D0000-0000-4000-8000-000000000001"
            }
          ]
        }
      ],
      "extraIncome" : [
        {
          "amount" : 250,
          "day" : 20,
          "id" : "7E4D0000-0000-4000-8000-000000000011",
          "isRecurring" : false,
          "kind" : "fixed",
          "name" : "Bijverdienste",
          "potShares" : [

          ]
        }
      ],
      "percentAllocations" : {
        "7E4D0000-0000-4000-8000-000000000002" : {
          "basis" : "salary",
          "percent" : 4.25
        },
        "7E4D0000-0000-4000-8000-000000000004" : {
          "basis" : "salary",
          "percent" : 8
        }
      }
    },
    "2026-04" : {
      "allocations" : {
        "7E4D0000-0000-4000-8000-000000000001" : 250,
        "7E4D0000-0000-4000-8000-000000000002" : 80,
        "7E4D0000-0000-4000-8000-000000000005" : 40
      },
      "expenses" : [

      ],
      "extraIncome" : [

      ],
      "hoursOverride" : 120.5,
      "percentAllocations" : {
        "7E4D0000-0000-4000-8000-000000000003" : {
          "basis" : "allIncome",
          "percent" : 3
        },
        "7E4D0000-0000-4000-8000-000000000004" : {
          "basis" : "allIncome",
          "percent" : 7.5
        }
      },
      "transferDay" : 7
    },
    "2026-05" : {
      "allocations" : {

      },
      "expenses" : [

      ],
      "extraIncome" : [

      ],
      "salaryOverride" : 2400
    }
  },
  "potEntries" : [
    {
      "amount" : 800,
      "date" : "2026-03-08T13:00:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000021",
      "kind" : "opening",
      "note" : "",
      "potID" : "7E4D0000-0000-4000-8000-000000000001"
    },
    {
      "amount" : -75,
      "date" : "2026-03-22T12:00:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000022",
      "kind" : "withdrawal",
      "note" : "Fiets",
      "potID" : "7E4D0000-0000-4000-8000-000000000001"
    }
  ],
  "pots" : [
    {
      "colorIndex" : 1,
      "createdAt" : "2026-01-02T12:00:00Z",
      "goalAmount" : 6000,
      "goalDate" : "2027-05-16T12:00:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000001",
      "interestPayout" : "monthly",
      "interestPayoutDay" : 1,
      "interestPayoutMonth" : 1,
      "interestRate" : 0.015,
      "monthlyContribution" : 200,
      "name" : "Buffer",
      "startMonth" : "2026-03",
      "symbol" : "shield.lefthalf.filled",
      "transferDay" : 5
    },
    {
      "colorIndex" : 3,
      "contributionMode" : "percentage",
      "contributionPercent" : 4.25,
      "createdAt" : "2026-01-03T12:00:00Z",
      "id" : "7E4D0000-0000-4000-8000-000000000002",
      "interestPayout" : "yearly",
      "interestPayoutDay" : 1,
      "interestPayoutMonth" : 1,
      "interestRate" : 0,
      "monthlyContribution" : 100,
      "name" : "Vakantie",
      "startMonth" : "2026-03",
      "symbol" : "airplane"
    },
    {
      "colorIndex" : 5,
      "contributionBasis" : "allIncome",
      "contributionMode" : "percentage",
      "contributionPercent" : 2,
      "createdAt" : "2026-01-04T12:00:00Z",
      "goalAmount" : 4000,
      "id" : "7E4D0000-0000-4000-8000-000000000003",
      "interestPayout" : "yearly",
      "interestPayoutDay" : 1,
      "interestPayoutMonth" : 1,
      "interestRate" : 0,
      "monthlyContribution" : 50,
      "name" : "Auto",
      "startMonth" : "2026-04",
      "symbol" : "car"
    }
  ],
  "salary" : {
    "fixedMonthly" : 0,
    "hourlyRate" : 17.5,
    "hoursPerWeek" : 36,
    "mode" : "hourly",
    "payDay" : 24
  },
  "settings" : {
    "autoRefreshPrices" : true,
    "bankBufferMonths" : 3,
    "blockOrder" : {

    },
    "defaultWithdrawalRate" : 0.04,
    "inflation" : 0.02,
    "savingsRate" : 0.02
  },
  "startDay" : "2026-03-12",
  "startMonth" : "2026-03",
  "version" : 1
}
"""

    /// `FinanceStorage.makeFileEncoder()`: compact, met dezelfde vaste volgorde van sleutels (het bestand op schijf).
    static let compact = """
{"appliedAccelerators":[],"bankEntries":[{"amount":60,"date":"2026-03-17T12:00:00Z","id":"7E4D0000-0000-4000-8000-000000000051","kind":"deposit","note":"Verjaardag"}],"bankSnapshots":[{"balance":2150.5,"date":"2026-03-12T12:30:00Z","id":"7E4D0000-0000-4000-8000-000000000041","note":"Begin"}],"goals":[{"funding":{"pot":{"_0":"7E4D0000-0000-4000-8000-000000000002"}},"hoursFrom":0,"hoursTo":0,"id":"7E4D0000-0000-4000-8000-000000000061","inflationAdjusted":true,"kind":"vacation","monthlySpending":0,"name":"Vakantie Japan","otherMonthlyIncome":0,"targetAmount":3500,"targetDate":"2026-10-28T12:00:00Z","withdrawalRate":0.04},{"funding":{"custom":{"annualReturn":0.03,"monthly":150,"start":500}},"hoursFrom":0,"hoursTo":0,"id":"7E4D0000-0000-4000-8000-000000000062","inflationAdjusted":true,"kind":"custom","monthlySpending":0,"name":"Camper","otherMonthlyIncome":0,"targetAmount":12000,"withdrawalRate":0.04},{"funding":{"portfolio":{}},"hoursFrom":0,"hoursTo":0,"id":"7E4D0000-0000-4000-8000-000000000063","inflationAdjusted":true,"kind":"retirement","monthlySpending":0,"name":"Pensioen","otherMonthlyIncome":0,"targetAmount":0,"withdrawalRate":0.04}],"holdings":[{"annualCost":0.002,"contributionMode":"percentage","contributionPercent":8,"expectedReturn":0.06,"id":"7E4D0000-0000-4000-8000-000000000004","investedTotal":900,"kind":"etf","lastPrice":119,"lastPriceDate":"2026-02-01T12:00:00Z","monthlyContribution":60,"name":"Wereldfonds","priceCurrency":"EUR","snapshots":[{"date":"2026-01-31T12:00:00Z","id":"7E4D0000-0000-4000-8000-000000000031","invested":900,"value":950}],"startMonth":"2026-03","ticker":"VWCE.DE","transferDay":12,"units":8},{"annualCost":0.001,"expectedReturn":0.03,"id":"7E4D0000-0000-4000-8000-000000000005","investedTotal":0,"kind":"etf","monthlyContribution":40,"name":"Obligaties","snapshots":[],"startMonth":"2026-03","units":0}],"homeHoldingIDs":["7E4D0000-0000-4000-8000-000000000004"],"homePotIDs":["7E4D0000-0000-4000-8000-000000000002","7E4D0000-0000-4000-8000-000000000001"],"modifiedAt":"2026-04-01T15:15:00Z","months":{"2026-03":{"allocations":{"7E4D0000-0000-4000-8000-000000000001":200,"7E4D0000-0000-4000-8000-000000000005":40},"expenses":[{"amount":950,"day":1,"id":"7E4D0000-0000-4000-8000-000000000013","isRecurring":true,"kind":"fixed","name":"Huur","potShares":[],"seriesID":"7E4D0000-0000-4000-8000-000000000014"},{"amount":120,"day":15,"id":"7E4D0000-0000-4000-8000-000000000015","isRecurring":false,"kind":"variable","name":"Fiets","potShares":[{"amount":50,"id":"7E4D0000-0000-4000-8000-000000000016","potID":"7E4D0000-0000-4000-8000-000000000001"}]}],"extraIncome":[{"amount":250,"day":20,"id":"7E4D0000-0000-4000-8000-000000000011","isRecurring":false,"kind":"fixed","name":"Bijverdienste","potShares":[]}],"percentAllocations":{"7E4D0000-0000-4000-8000-000000000002":{"basis":"salary","percent":4.25},"7E4D0000-0000-4000-8000-000000000004":{"basis":"salary","percent":8}}},"2026-04":{"allocations":{"7E4D0000-0000-4000-8000-000000000001":250,"7E4D0000-0000-4000-8000-000000000002":80,"7E4D0000-0000-4000-8000-000000000005":40},"expenses":[],"extraIncome":[],"hoursOverride":120.5,"percentAllocations":{"7E4D0000-0000-4000-8000-000000000003":{"basis":"allIncome","percent":3},"7E4D0000-0000-4000-8000-000000000004":{"basis":"allIncome","percent":7.5}},"transferDay":7},"2026-05":{"allocations":{},"expenses":[],"extraIncome":[],"salaryOverride":2400}},"potEntries":[{"amount":800,"date":"2026-03-08T13:00:00Z","id":"7E4D0000-0000-4000-8000-000000000021","kind":"opening","note":"","potID":"7E4D0000-0000-4000-8000-000000000001"},{"amount":-75,"date":"2026-03-22T12:00:00Z","id":"7E4D0000-0000-4000-8000-000000000022","kind":"withdrawal","note":"Fiets","potID":"7E4D0000-0000-4000-8000-000000000001"}],"pots":[{"colorIndex":1,"createdAt":"2026-01-02T12:00:00Z","goalAmount":6000,"goalDate":"2027-05-16T12:00:00Z","id":"7E4D0000-0000-4000-8000-000000000001","interestPayout":"monthly","interestPayoutDay":1,"interestPayoutMonth":1,"interestRate":0.015,"monthlyContribution":200,"name":"Buffer","startMonth":"2026-03","symbol":"shield.lefthalf.filled","transferDay":5},{"colorIndex":3,"contributionMode":"percentage","contributionPercent":4.25,"createdAt":"2026-01-03T12:00:00Z","id":"7E4D0000-0000-4000-8000-000000000002","interestPayout":"yearly","interestPayoutDay":1,"interestPayoutMonth":1,"interestRate":0,"monthlyContribution":100,"name":"Vakantie","startMonth":"2026-03","symbol":"airplane"},{"colorIndex":5,"contributionBasis":"allIncome","contributionMode":"percentage","contributionPercent":2,"createdAt":"2026-01-04T12:00:00Z","goalAmount":4000,"id":"7E4D0000-0000-4000-8000-000000000003","interestPayout":"yearly","interestPayoutDay":1,"interestPayoutMonth":1,"interestRate":0,"monthlyContribution":50,"name":"Auto","startMonth":"2026-04","symbol":"car"}],"salary":{"fixedMonthly":0,"hourlyRate":17.5,"hoursPerWeek":36,"mode":"hourly","payDay":24},"settings":{"autoRefreshPrices":true,"bankBufferMonths":3,"blockOrder":{},"defaultWithdrawalRate":0.04,"inflation":0.02,"savingsRate":0.02},"startDay":"2026-03-12","startMonth":"2026-03","version":1}
"""
}
