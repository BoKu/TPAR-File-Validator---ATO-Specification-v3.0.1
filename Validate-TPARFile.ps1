<#
.SYNOPSIS
    TPAR File Validator - Validates Taxable Payments Annual Report text files
.DESCRIPTION
    Validates TPAR files against the ATO specification v3.0.1
    Checks record structure, field formats, data types, and business rules
.PARAMETER FilePath
    Path to the TPAR text file to validate
.EXAMPLE
    .\Validate-TPARFile.ps1 -FilePath "C:\TPAR\TPAR_2026.txt"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

# Colour output functions
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }

# Validation state tracking
$script:ErrorCount = 0
$script:WarningCount = 0
$script:RecordCount = 0
$script:PayeeRecordCount = 0

# Add validation error
function Add-ValidationError {
    param(
        [int]$LineNumber,
        [string]$RecordType,
        [string]$FieldName,
        [string]$Message
    )
    $script:ErrorCount++
    Write-Error "ERROR [Line $LineNumber, $RecordType, $FieldName]: $Message"
}

# Add validation warning
function Add-ValidationWarning {
    param(
        [int]$LineNumber,
        [string]$RecordType,
        [string]$FieldName,
        [string]$Message
    )
    $script:WarningCount++
    Write-Warning "WARNING [Line $LineNumber, $RecordType, $FieldName]: $Message"
}

# Validate ABN using ATO algorithm
function Test-ABN {
    param([string]$ABN)
    
    if ($ABN -match '^\d{11}$') {
        $weights = @(10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19)
        $abnArray = $ABN.ToCharArray() | ForEach-Object { [int]::Parse($_) }
        $abnArray[0] = $abnArray[0] - 1
        
        $sum = 0
        for ($i = 0; $i -lt 11; $i++) {
            $sum += $abnArray[$i] * $weights[$i]
        }
        
        return ($sum % 89) -eq 0
    }
    return $false
}

# Validate date format DDMMCCYY
function Test-DateFormat {
    param([string]$DateString)
    
    if ($DateString -match '^\d{8}$') {
        try {
            $day = [int]$DateString.Substring(0, 2)
            $month = [int]$DateString.Substring(2, 2)
            $year = [int]$DateString.Substring(4, 4)
            
            $date = Get-Date -Year $year -Month $month -Day $day -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
    return $false
}

# Validate postcode
function Test-Postcode {
    param([string]$Postcode)
    
    if ($Postcode -match '^\d{4}$') {
        $code = [int]$Postcode
        return ($code -ge 0 -and $code -le 9999)
    }
    return $false
}

# Validate state code
function Test-StateCode {
    param([string]$State)
    
    $validStates = @('ACT', 'NSW', 'NT', 'QLD', 'SA', 'TAS', 'VIC', 'WA', 'OTH')
    return $validStates -contains $State.Trim()
}

# Validate email format
function Test-Email {
    param([string]$Email)
    
    if ([string]::IsNullOrWhiteSpace($Email)) {
        return $true  # Optional field
    }
    
    $trimmed = $Email.Trim()
    $atPos = $trimmed.IndexOf('@')
    
    return ($atPos -gt 0 -and $atPos -lt ($trimmed.Length - 1))
}

# Extract field from record
function Get-Field {
    param(
        [string]$Record,
        [int]$Start,
        [int]$Length
    )
    
    if ($Record.Length -ge ($Start + $Length - 1)) {
        return $Record.Substring($Start - 1, $Length)
    }
    return ""
}

# Validate mandatory alpha field
function Test-MandatoryAlpha {
    param(
        [string]$Value,
        [int]$LineNumber,
        [string]$RecordType,
        [string]$FieldName
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Mandatory field is blank"
        return $false
    }
    
    if ($Value.StartsWith(' ')) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Field must not start with blank"
        return $false
    }
    
    return $true
}

# Validate mandatory alphanumeric field
function Test-MandatoryAlphaNumeric {
    param(
        [string]$Value,
        [int]$LineNumber,
        [string]$RecordType,
        [string]$FieldName
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Mandatory field is blank"
        return $false
    }
    
    if ($Value.StartsWith(' ')) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Field must not start with blank"
        return $false
    }
    
    # Check for double spaces
    if ($Value -match '  ') {
        Add-ValidationWarning $LineNumber $RecordType $FieldName "Field contains consecutive spaces"
    }
    
    return $true
}

# Validate mandatory numeric field
function Test-MandatoryNumeric {
    param(
        [string]$Value,
        [int]$LineNumber,
        [string]$RecordType,
        [string]$FieldName,
        [bool]$CanBeZero = $true
    )
    
    if (-not ($Value -match '^\d+$')) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Field must contain only digits"
        return $false
    }
    
    if (-not $CanBeZero -and ([int64]$Value -eq 0)) {
        Add-ValidationError $LineNumber $RecordType $FieldName "Field must be greater than zero"
        return $false
    }
    
    return $true
}

# Validate Sender Data Record 1
function Test-SenderRecord1 {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 14
    $senderABN = Get-Field $Record 18 11
    $runType = Get-Field $Record 29 1
    $reportEndDate = Get-Field $Record 30 8
    $dataType = Get-Field $Record 38 1
    $typeOfReport = Get-Field $Record 39 1
    $formatMedia = Get-Field $Record 40 1
    $versionNumber = Get-Field $Record 41 10
    
    Write-Info "Validating Sender Data Record 1 (Line $LineNumber)"
    
    # Record Length
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "SENDER1" "RecordLength" "Must be 996, found: $recordLength"
    }
    
    # Record Identifier
    if ($recordId.Trim() -ne "IDENTREGISTER1") {
        Add-ValidationError $LineNumber "SENDER1" "RecordId" "Must be 'IDENTREGISTER1', found: '$($recordId.Trim())'"
    }
    
    # Sender ABN
    if (-not (Test-ABN $senderABN)) {
        Add-ValidationError $LineNumber "SENDER1" "SenderABN" "Invalid ABN: $senderABN"
    }
    
    # Run Type
    if ($runType -notmatch '^[TP]$') {
        Add-ValidationError $LineNumber "SENDER1" "RunType" "Must be 'T' or 'P', found: '$runType'"
    }
    
    # Report End Date
    if (-not (Test-DateFormat $reportEndDate)) {
        Add-ValidationError $LineNumber "SENDER1" "ReportEndDate" "Invalid date format: $reportEndDate"
    }
    
    # Data Type
    if ($dataType -ne "P") {
        Add-ValidationError $LineNumber "SENDER1" "DataType" "Must be 'P', found: '$dataType'"
    }
    
    # Type of Report
    if ($typeOfReport -ne "C") {
        Add-ValidationError $LineNumber "SENDER1" "TypeOfReport" "Must be 'C', found: '$typeOfReport'"
    }
    
    # Format Media
    if ($formatMedia -ne "M") {
        Add-ValidationError $LineNumber "SENDER1" "FormatMedia" "Must be 'M', found: '$formatMedia'"
    }
    
    # Version Number
    if ($versionNumber.Trim() -ne "FPAIVV03.0") {
        Add-ValidationError $LineNumber "SENDER1" "VersionNumber" "Must be 'FPAIVV03.0', found: '$($versionNumber.Trim())'"
    }
}

# Validate Sender Data Record 2
function Test-SenderRecord2 {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 14
    $senderName = Get-Field $Record 18 200
    $contactName = Get-Field $Record 218 38
    $contactPhone = Get-Field $Record 256 15
    
    Write-Info "Validating Sender Data Record 2 (Line $LineNumber)"
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "SENDER2" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "IDENTREGISTER2") {
        Add-ValidationError $LineNumber "SENDER2" "RecordId" "Must be 'IDENTREGISTER2'"
    }
    
    Test-MandatoryAlphaNumeric $senderName $LineNumber "SENDER2" "SenderName"
    Test-MandatoryAlphaNumeric $contactName $LineNumber "SENDER2" "ContactName"
    Test-MandatoryAlphaNumeric $contactPhone $LineNumber "SENDER2" "ContactPhone"
}

# Validate Sender Data Record 3
function Test-SenderRecord3 {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 14
    $streetAddr1 = Get-Field $Record 18 38
    $suburb = Get-Field $Record 94 27
    $state = Get-Field $Record 121 3
    $postcode = Get-Field $Record 124 4
    $emailAddr = Get-Field $Record 278 76
    
    Write-Info "Validating Sender Data Record 3 (Line $LineNumber)"
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "SENDER3" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "IDENTREGISTER3") {
        Add-ValidationError $LineNumber "SENDER3" "RecordId" "Must be 'IDENTREGISTER3'"
    }
    
    Test-MandatoryAlphaNumeric $streetAddr1 $LineNumber "SENDER3" "StreetAddress1"
    Test-MandatoryAlphaNumeric $suburb $LineNumber "SENDER3" "Suburb"
    
    if (-not (Test-StateCode $state)) {
        Add-ValidationError $LineNumber "SENDER3" "State" "Invalid state code: '$($state.Trim())'"
    }
    
    if (-not (Test-Postcode $postcode)) {
        Add-ValidationError $LineNumber "SENDER3" "Postcode" "Invalid postcode: $postcode"
    }
    
    if (-not (Test-Email $emailAddr)) {
        Add-ValidationError $LineNumber "SENDER3" "Email" "Invalid email format"
    }
}

# Validate Payer Identity Data Record
function Test-PayerIdentityRecord {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 8
    $payerABN = Get-Field $Record 12 11
    $branchNumber = Get-Field $Record 23 3
    $financialYear = Get-Field $Record 26 4
    $payerName = Get-Field $Record 30 200
    $payerAddr1 = Get-Field $Record 430 38
    $payerSuburb = Get-Field $Record 506 27
    $payerState = Get-Field $Record 533 3
    $payerPostcode = Get-Field $Record 536 4
    
    Write-Info "Validating Payer Identity Data Record (Line $LineNumber)"
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "PAYER" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "IDENTITY") {
        Add-ValidationError $LineNumber "PAYER" "RecordId" "Must be 'IDENTITY'"
    }
    
    if (-not (Test-ABN $payerABN)) {
        Add-ValidationError $LineNumber "PAYER" "PayerABN" "Invalid ABN: $payerABN"
    }
    
    # Branch number must be numeric (001 minimum)
    if (-not ($branchNumber -match '^\d{3}$')) {
        Add-ValidationError $LineNumber "PAYER" "BranchNumber" "Must be 3-digit number: $branchNumber"
    }
    
    # Financial year validation
    $currentYear = (Get-Date).Year
    $yearValue = [int]$financialYear
    if ($yearValue -lt 2013 -or $yearValue -gt $currentYear) {
        Add-ValidationError $LineNumber "PAYER" "FinancialYear" "Year $yearValue is out of valid range (2013-$currentYear)"
    }
    
    Test-MandatoryAlphaNumeric $payerName $LineNumber "PAYER" "PayerName"
    Test-MandatoryAlphaNumeric $payerAddr1 $LineNumber "PAYER" "PayerAddress"
    Test-MandatoryAlphaNumeric $payerSuburb $LineNumber "PAYER" "PayerSuburb"
    
    if (-not (Test-StateCode $payerState)) {
        Add-ValidationError $LineNumber "PAYER" "State" "Invalid state code: '$($payerState.Trim())'"
    }
    
    if (-not (Test-Postcode $payerPostcode)) {
        Add-ValidationError $LineNumber "PAYER" "Postcode" "Invalid postcode: $payerPostcode"
    }
}

# Validate Software Data Record
function Test-SoftwareRecord {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 8
    $softwareProduct = Get-Field $Record 12 80
    
    Write-Info "Validating Software Data Record (Line $LineNumber)"
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "SOFTWARE" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "SOFTWARE") {
        Add-ValidationError $LineNumber "SOFTWARE" "RecordId" "Must be 'SOFTWARE'"
    }
    
    Test-MandatoryAlphaNumeric $softwareProduct $LineNumber "SOFTWARE" "SoftwareProduct"
}

# Validate Payee Data Record
function Test-PayeeRecord {
    param([string]$Record, [int]$LineNumber)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 6
    $payeeABN = Get-Field $Record 10 11
    $surname = Get-Field $Record 21 30
    $firstName = Get-Field $Record 51 15
    $businessName = Get-Field $Record 81 200
    $address1 = Get-Field $Record 481 38
    $suburb = Get-Field $Record 557 27
    $state = Get-Field $Record 584 3
    $postcode = Get-Field $Record 587 4
    $grossAmount = Get-Field $Record 641 11
    $totalTaxWithheld = Get-Field $Record 652 11
    $totalGST = Get-Field $Record 663 11
    $paymentType = Get-Field $Record 674 1
    $grantDate = Get-Field $Record 675 8
    $grantName = Get-Field $Record 683 200
    $statementBySupplier = Get-Field $Record 959 1
    $amendmentIndicator = Get-Field $Record 960 1
    $nane = Get-Field $Record 961 1
    
    Write-Info "Validating Payee Data Record (Line $LineNumber)"
    $script:PayeeRecordCount++
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "PAYEE" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "DPAIVS") {
        Add-ValidationError $LineNumber "PAYEE" "RecordId" "Must be 'DPAIVS'"
    }
    
    # ABN validation
    if ($payeeABN -ne "00000000000") {
        if (-not (Test-ABN $payeeABN)) {
            Add-ValidationError $LineNumber "PAYEE" "PayeeABN" "Invalid ABN: $payeeABN"
        }
    }
    
    # Name validation - either individual name OR business name required
    $hasSurname = -not [string]::IsNullOrWhiteSpace($surname)
    $hasFirstName = -not [string]::IsNullOrWhiteSpace($firstName)
    $hasBusinessName = -not [string]::IsNullOrWhiteSpace($businessName)
    
    if ($hasBusinessName -and ($hasSurname -or $hasFirstName)) {
        # Both individual and business name present - acceptable
    }
    elseif ($hasBusinessName -or ($hasSurname -and $hasFirstName)) {
        # Either business name OR both surname and first name - valid
    }
    else {
        Add-ValidationError $LineNumber "PAYEE" "Name" "Must have either Business Name OR (Surname AND First Name)"
    }
    
    # Address validation
    Test-MandatoryAlphaNumeric $address1 $LineNumber "PAYEE" "Address"
    Test-MandatoryAlphaNumeric $suburb $LineNumber "PAYEE" "Suburb"
    
    if (-not (Test-StateCode $state)) {
        Add-ValidationError $LineNumber "PAYEE" "State" "Invalid state code: '$($state.Trim())'"
    }
    
    if (-not (Test-Postcode $postcode)) {
        Add-ValidationError $LineNumber "PAYEE" "Postcode" "Invalid postcode: $postcode"
    }
    
    # Amount validation
    if (-not (Test-MandatoryNumeric $grossAmount $LineNumber "PAYEE" "GrossAmount" $false)) {
        # Gross amount must be greater than zero
    }
    
    Test-MandatoryNumeric $totalTaxWithheld $LineNumber "PAYEE" "TotalTaxWithheld"
    Test-MandatoryNumeric $totalGST $LineNumber "PAYEE" "TotalGST"
    
    # Payment Type validation
    if ($paymentType -notmatch '^[GP]$') {
        Add-ValidationError $LineNumber "PAYEE" "PaymentType" "Must be 'G' or 'P', found: '$paymentType'"
    }
    
    # Conditional validation for grants
    if ($paymentType -eq "G") {
        if (-not (Test-DateFormat $grantDate)) {
            Add-ValidationError $LineNumber "PAYEE" "GrantDate" "Grant date required and must be valid when Payment Type is 'G'"
        }
        
        if ([string]::IsNullOrWhiteSpace($grantName)) {
            Add-ValidationError $LineNumber "PAYEE" "GrantName" "Grant name required when Payment Type is 'G'"
        }
    }
    else {
        if ($grantDate -ne "00000000") {
            Add-ValidationWarning $LineNumber "PAYEE" "GrantDate" "Grant date should be zero-filled when Payment Type is 'P'"
        }
        
        if (-not [string]::IsNullOrWhiteSpace($grantName)) {
            Add-ValidationWarning $LineNumber "PAYEE" "GrantName" "Grant name should be blank when Payment Type is 'P'"
        }
    }
    
    # Statement by Supplier
    if ($statementBySupplier -notmatch '^[YN]$') {
        Add-ValidationError $LineNumber "PAYEE" "StatementBySupplier" "Must be 'Y' or 'N', found: '$statementBySupplier'"
    }
    
    # Amendment Indicator
    if ($amendmentIndicator -notmatch '^[OA]$') {
        Add-ValidationError $LineNumber "PAYEE" "AmendmentIndicator" "Must be 'O' or 'A', found: '$amendmentIndicator'"
    }
    
    # NANE validation
    if (-not [string]::IsNullOrWhiteSpace($nane)) {
        if ($nane -notmatch '^[NYU]$') {
            Add-ValidationError $LineNumber "PAYEE" "NANE" "Must be 'N', 'Y', or 'U', found: '$nane'"
        }
    }
}

# Validate File Total Data Record
function Test-FileTotalRecord {
    param([string]$Record, [int]$LineNumber, [int]$ExpectedCount)
    
    $recordLength = Get-Field $Record 1 3
    $recordId = Get-Field $Record 4 10
    $numRecords = Get-Field $Record 14 8
    
    Write-Info "Validating File Total Data Record (Line $LineNumber)"
    
    if ($recordLength -ne "996") {
        Add-ValidationError $LineNumber "FILETOTAL" "RecordLength" "Must be 996"
    }
    
    if ($recordId.Trim() -ne "FILE-TOTAL") {
        Add-ValidationError $LineNumber "FILETOTAL" "RecordId" "Must be 'FILE-TOTAL'"
    }
    
    $countValue = [int]$numRecords
    if ($countValue -ne $ExpectedCount) {
        Add-ValidationError $LineNumber "FILETOTAL" "RecordCount" "Record count mismatch: File total shows $countValue, actual count is $ExpectedCount"
    }
    else {
        Write-Success "Record count validated: $countValue records"
    }
}

# Main validation function
function Start-TPARValidation {
    param([string]$FilePath)
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TPAR File Validator v1.0" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Check file exists
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }
    
    # Get file info
    $fileInfo = Get-Item $FilePath
    Write-Info "File: $($fileInfo.Name)"
    Write-Info "Size: $($fileInfo.Length) bytes"
    Write-Info "Modified: $($fileInfo.LastWriteTime)`n"
    
    # Read file
    try {
        $lines = Get-Content $FilePath -Encoding Default
    }
    catch {
        Write-Error "Failed to read file: $_"
        return
    }
    
    if ($lines.Count -eq 0) {
        Write-Error "File is empty"
        return
    }
    
    Write-Info "Total lines: $($lines.Count)`n"
    
    # Validate record length
    Write-Info "Checking record lengths..."
    $recordLength = 996
    $hasLengthErrors = $false
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $actualLength = $line.Length
        
        # Account for CR/LF if present
        if ($actualLength -eq 998) {
            Write-Info "Line $($i+1): Detected CR/LF (length 998)"
        }
        elseif ($actualLength -ne $recordLength) {
            Add-ValidationError ($i + 1) "STRUCTURE" "RecordLength" "Expected $recordLength chars, found $actualLength chars"
            $hasLengthErrors = $true
        }
    }
    
    if (-not $hasLengthErrors) {
        Write-Success "All records are correct length ($recordLength characters)`n"
    }
    
    # Validate file structure
    Write-Info "`nValidating file structure...`n"
    
    $lineNum = 0
    $expectedStructure = @(
        "IDENTREGISTER1",  # Sender 1
        "IDENTREGISTER2",  # Sender 2
        "IDENTREGISTER3",  # Sender 3
        "IDENTITY",        # Payer Identity (repeatable group starts)
        "SOFTWARE",        # Software
        "DPAIVS"           # Payee (1 or more)
    )
    
    # Validate first 3 records must be Sender records
    if ($lines.Count -lt 3) {
        Write-Error "File must contain at least 3 Sender records"
        return
    }
    
    # Validate Sender Records
    Test-SenderRecord1 $lines[0] 1
    $script:RecordCount++
    
    Test-SenderRecord2 $lines[1] 2
    $script:RecordCount++
    
    Test-SenderRecord3 $lines[2] 3
    $script:RecordCount++
    
    # Process remaining records
    $lineNum = 3
    $inPayerGroup = $false
    $expectingSoftware = $false
    $expectingPayee = $false
    
    while ($lineNum -lt $lines.Count) {
        $line = $lines[$lineNum]
        $recordId = Get-Field $line 4 14
        $recordIdTrimmed = $recordId.Trim()
        
        Write-Host "`nLine $($lineNum + 1): Record Type = $recordIdTrimmed" -ForegroundColor Gray
        
        switch ($recordIdTrimmed) {
            "IDENTITY" {
                Test-PayerIdentityRecord $line ($lineNum + 1)
                $script:RecordCount++
                $expectingSoftware = $true
                $expectingPayee = $false
            }
            "SOFTWARE" {
                if (-not $expectingSoftware) {
                    Add-ValidationError ($lineNum + 1) "STRUCTURE" "Order" "SOFTWARE record must follow IDENTITY record"
                }
                Test-SoftwareRecord $line ($lineNum + 1)
                $script:RecordCount++
                $expectingSoftware = $false
                $expectingPayee = $true
            }
            "DPAIVS" {
                if (-not $expectingPayee) {
                    Add-ValidationError ($lineNum + 1) "STRUCTURE" "Order" "PAYEE record must follow SOFTWARE record"
                }
                Test-PayeeRecord $line ($lineNum + 1)
                $script:RecordCount++
            }
            "FILE-TOTAL" {
                Test-FileTotalRecord $line ($lineNum + 1) ($lineNum + 1)
                $script:RecordCount++
                
                if ($lineNum -ne ($lines.Count - 1)) {
                    Add-ValidationError ($lineNum + 1) "STRUCTURE" "Order" "FILE-TOTAL must be the last record"
                }
                break
            }
            default {
                Add-ValidationError ($lineNum + 1) "STRUCTURE" "RecordType" "Unknown record identifier: '$recordIdTrimmed'"
                $script:RecordCount++
            }
        }
        
        $lineNum++
    }
    
    # Check if file has FILE-TOTAL record
    if ($lines.Count -gt 0) {
        $lastLine = $lines[$lines.Count - 1]
        $lastRecordId = (Get-Field $lastLine 4 10).Trim()
        
        if ($lastRecordId -ne "FILE-TOTAL") {
            Add-ValidationError $lines.Count "STRUCTURE" "Missing" "FILE-TOTAL record missing at end of file"
        }
    }
    
    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Records Processed: $script:RecordCount" -ForegroundColor White
    Write-Host "Payee Records Found: $script:PayeeRecordCount" -ForegroundColor White
    Write-Host "Errors Found: $script:ErrorCount" -ForegroundColor $(if ($script:ErrorCount -eq 0) { "Green" } else { "Red" })
    Write-Host "Warnings Found: $script:WarningCount" -ForegroundColor $(if ($script:WarningCount -eq 0) { "Green" } else { "Yellow" })
    
    if ($script:ErrorCount -eq 0 -and $script:WarningCount -eq 0) {
        Write-Host "[Y] - VALIDATION PASSED - File is valid!" -ForegroundColor Green
    }
    elseif ($script:ErrorCount -eq 0) {
        Write-Host "[!] - VALIDATION PASSED WITH WARNINGS" -ForegroundColor Yellow
    }
    else {
        Write-Host "[N] - VALIDATION FAILED - Please fix errors above" -ForegroundColor Red
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Execute validation
Start-TPARValidation -FilePath $FilePath
