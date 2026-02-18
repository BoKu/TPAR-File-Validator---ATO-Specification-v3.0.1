# TPAR File Validator (PowerShell)

TPAR File Validator is a PowerShell script that validates **Taxable Payments Annual Report** (TPAR) fixed‑width text files against the Australian Taxation Office (ATO) electronic reporting specification v3.0.1.

It is intended for finance, payroll and software teams who need a quick, scriptable way to pre‑check TPAR exports before lodgement

---

## Features

- Validates file against ATO TPAR v3.0.1 layout (record order and structure).
- Confirms every record is the expected 996 characters (with CR/LF handling).
- Validates all mandatory record types:
  - Sender Data Records 1–3 (IDENTREGISTER1/2/3).
  - Payer Identity Data Record (IDENTITY).
  - Software Data Record (SOFTWARE).
  - Payee Data Records (DPAIVS).
  - File Total Data Record (FILE‑TOTAL).
- Performs detailed field‑level checks, including:
  - ABN validation using the official ATO modulus 89 algorithm.
  - Dates in DDMMYYYY format with real calendar validation.
  - Australian postcodes and state codes (ACT, NSW, NT, QLD, SA, TAS, VIC, WA, OTH).
  - Email address basic structure checks.
  - Mandatory alpha, alphanumeric and numeric fields, with warnings for consecutive spaces.
- Enforces business rules, for example:
  - Correct run type, data type, type of report, format media and version in Sender Record 1.
  - Financial year between 2013 and the current year.
  - Either business name **or** both surname and first name for payees.
  - Grant‑specific rules when payment type is G (grant) vs P (payment).
  - Valid ranges and values for Statement by Supplier, Amendment Indicator and NANE flag fields.
- Summarises validation with coloured console output:
  - Total records processed and payee records found.
  - Total errors and warnings.
  - Clear final status: passed, passed with warnings, or failed.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+.
- Permission to read the TPAR text file from the specified path.

The script is self‑contained and uses only built‑in PowerShell cmdlets and .NET types.

---

## Usage

Open a PowerShell prompt and run:

```powershell
.\Validate-TPARFile.ps1 -FilePath "C:\TPAR\TPAR_2026.txt"
