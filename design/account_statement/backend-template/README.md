# BocTrust account statement — PDF template

The HTML template for the account statement PDF that is emailed to customers. It uses the same colours, type and card style as the BocTrust mobile app.

| File | Purpose |
|---|---|
| `statement.html` | The template. Logic-less Mustache syntax, so it also works with Handlebars (and any Mustache port: Go, Java, .NET, Python, PHP). |
| `sample-data.json` | A complete example of the data the template expects (fictional customer). |
| `logo.svg` | The BocTrust app icon. |
| `fonts/` | Plus Jakarta Sans (SIL Open Font License) and the FH Oscar trial build (`FHOscarTest-*`) — see **Fonts**. |

## Rendering

Render with a Chromium-based engine (Puppeteer, Playwright, Gotenberg, or headless Chrome). WeasyPrint and wkhtmltopdf aren't supported: they lack parts of the CSS used (grid, `clip-path`).

1. Fill `statement.html` with the statement data.
2. Load the result so that `logo.svg` and `fonts/` resolve relative to it: either write it next to those files and open it by `file://` URL, or add `<base href="…/">` pointing at the folder.
3. Wait for fonts (`document.fonts.ready`), then print to PDF with **A4**, **print backgrounds on**, and **`preferCSSPageSize: true`**. The page margins are set in the template (`@page`).
4. Add the page footer through the renderer. Chromium can't number pages from CSS, so the footer goes in `footerTemplate`.

Puppeteer example:

```js
const page = await browser.newPage();
await page.goto(`file://${dir}/statement.filled.html`, { waitUntil: 'networkidle0' });
await page.evaluate(() => document.fonts.ready);
const pdf = await page.pdf({
  format: 'A4',
  printBackground: true,
  preferCSSPageSize: true,
  displayHeaderFooter: true,
  headerTemplate: '<span></span>',
  footerTemplate: `
    <div style="width:100%;margin:0 16mm;padding-top:3mm;border-top:1px solid #E7E2D6;
                display:flex;justify-content:space-between;
                font-family:Helvetica,Arial,sans-serif;font-size:7pt;color:#5C636C;">
      <span><b style="color:#142B45">BocTrust</b> · Account ${maskedAccountNumber} · ${periodLabel}</span>
      <span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span>
    </div>`,
});
```

The footer template runs separately from the page, so it can't use the page's fonts or the main data. Insert its values as text, and HTML-escape them. The table header repeats on every page, and rows never split across pages.

## Data contract

The backend formats every value before rendering. The template does no maths and no date or number formatting.

```jsonc
{
  "statement": {
    "periodLabel": "1 Sep 2026 – 30 Sep 2026",
    "generatedAt": "1 Oct 2026, 08:14"          // WAT
  },
  "account": {
    "holderName": "Adaeze N. Okafor",
    "addressLines": ["14 Admiralty Way, Lekki Phase 1", "Lagos, Nigeria"],
    "number": "0123 456 789",                    // grouped 4-3-3
    "productName": "Boc Flex Savings",
    "currencyLabel": "Nigerian Naira (NGN)"
  },
  "summary": {
    "openingBalance": "184,250.00",              // no ₦ — the template adds it
    "openingDate": "1 Sep 2026",
    "openingDateShort": "01 Sep",
    "moneyIn": "612,400.00",
    "creditCountLabel": "7 credits",             // "1 credit" when singular
    "moneyOut": "431,875.50",
    "debitCountLabel": "13 debits",
    "closingBalance": "364,774.50",
    "closingDate": "30 Sep 2026",
    "closingDateShort": "30 Sep"
  },
  "transactions": [                              // oldest first; [] shows "No transactions in this period."
    {
      "date": "02 Sep",
      "time": "18:40",                           // 24-hour, WAT
      "description": "Transfer to Chinedu Eze",
      "detail": "GTBank",                        // optional second line
      "reference": "BT2609021840C",
      "moneyOut": "45,000.00",                   // set exactly one of moneyOut / moneyIn,
      "moneyIn": null,                           // positive, no sign — the template adds − / +
      "balance": "489,250.00"                    // running balance after this row
    }
  ],
  "bank": {
    "legalName": "…",
    "address": "…",
    "supportEmail": "…",
    "phone": "…",
    "regulatoryNotice": "…",                     // licensing / deposit-insurance line from Compliance
    "disputeWindowDays": "30"
  }
}
```

Rules:

- **Amounts:** two decimals with thousands separators, no currency sign. A negative balance (overdraft) is passed with a leading `−`.
- **`moneyOut` / `moneyIn`:** omit or `null` the side that doesn't apply. An empty string also counts as absent.
- **Masking:** phone numbers and card-like values in `detail` are masked before rendering (for example `0803 *** 4471`). The template prints what it's given.
- **Escaping:** the template uses `{{ }}`, so all values are HTML-escaped. Don't change these to `{{{ }}}`.
- **Totals:** must match the rows — `openingBalance + moneyIn − moneyOut = closingBalance`, and the last row's `balance` equals `closingBalance`.

## Fonts

- **Plus Jakarta Sans** (included) is used for all text. It's under the SIL Open Font License, so it can be embedded in PDFs.
- **FH Oscar** is the figures font (amounts, balances, account numbers, dates), as in the app. `fonts/` contains the same `FHOscarTest-*` files the app ships, which appear to be **trial builds**; BocTrust hasn't yet confirmed a commercial licence that covers embedding in PDFs. Before go-live, replace them with the licensed files and update the three `@font-face` URLs in `statement.html` if the file names change. If the files are missing, figures fall back to Plus Jakarta Sans with fixed-width (tabular) digits, and the layout still fits.

## Before go-live

- [ ] Fill the `bank` fields with copy approved by Compliance (legal name, address, contacts, regulatory notice, dispute window).
- [ ] Replace the FH Oscar trial files with licensed ones (see **Fonts**).
- [ ] Render the sample data, a statement with hundreds of rows, and an empty statement. Check page breaks and that the footer reads "Page X of Y".
- [ ] Confirm the PDF's title metadata: Puppeteer takes it from `<title>`.
