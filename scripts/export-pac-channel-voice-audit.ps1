<#
.SYNOPSIS
  Exporta para Excel quanto tempo cada utilizador ficou com systemuser.pac_channel_voice = true / false,
  reconstruindo o histórico a partir da auditoria do Dataverse (Web API, somente leitura).

.DESCRIPTION
  - Só faz GET. Nenhuma escrita no Dataverse.
  - Autenticação interativa por device code; o token fica apenas em memória e não é gravado.
  - A conta precisa ler auditoria (prvReadAuditSummary e prvReadRecordAuditHistory).
  - O Excel contém dados pessoais (nome, login). Por padrão vai para Documentos, fora do repositório.

  Lógica do cálculo, por utilizador:
  1. Estado no início = valor novo da última alteração auditada antes do início;
     senão, valor antigo da primeira alteração depois do início;
     senão, valor atual em systemuser.
  2. Cada alteração dentro do período abre um novo intervalo, que vai até a próxima alteração ou até o fim.
  3. Soma os minutos por estado (true, false, sem valor).

.EXAMPLE
  ./scripts/export-pac-channel-voice-audit.ps1 -EnvironmentUrl https://contoso.crm4.dynamics.com

.EXAMPLE
  ./scripts/export-pac-channel-voice-audit.ps1 -Inicio 2026-10-01 -Fim 2026-10-27 -TimeZoneId UTC
#>
[CmdletBinding()]
param(
    # URL base do ambiente (sem /api/...). Padrão: variável de usuário MDCC_DATAVERSE_URL.
    [string]$EnvironmentUrl = $env:MDCC_DATAVERSE_URL,
    # Início do período (inclusivo), no fuso de -TimeZoneId.
    [datetime]$Inicio = '2026-10-01',
    # Fim do período (exclusivo), no fuso de -TimeZoneId. Limitado a "agora".
    [datetime]$Fim = '2026-10-27',
    # Desde quando ler a auditoria para descobrir o estado no início do período.
    [datetime]$HistoricoDesde = '2026-01-01',
    # Fuso usado para interpretar Inicio/Fim e mostrar datas. 'GMT Standard Time' = Lisboa.
    [string]$TimeZoneId = 'GMT Standard Time',
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('pac_channel_voice_{0:yyyyMMdd_HHmm}.xlsx' -f (Get-Date))),
    # Inclui utilizadores desativados (isdisabled = true).
    [switch]$IncluirDesativados,
    [string]$TenantId = 'organizations',
    # Cliente público do Azure CLI, que aceita device code para o Dataverse.
    [string]$ClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
)

$ErrorActionPreference = 'Stop'
$Attribute = 'pac_channel_voice'

if ([string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
    throw 'Informe -EnvironmentUrl ou defina a variável de usuário MDCC_DATAVERSE_URL.'
}
$EnvironmentUrl = ($EnvironmentUrl.TrimEnd('/') -replace '/api/.*$', '')
$apiBase = "$EnvironmentUrl/api/data/v9.2"

$tz = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
function ConvertFrom-LocalToUtc([datetime]$d) {
    [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($d, 'Unspecified'), $tz)
}
function ConvertTo-Local([datetime]$utc) {
    [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind($utc, 'Utc'), $tz)
}
function ConvertTo-UtcDate($v) {
    if ($v -is [datetime]) {
        switch ($v.Kind) {
            'Utc' { return $v }
            'Local' { return $v.ToUniversalTime() }
            default { return [datetime]::SpecifyKind($v, 'Utc') }
        }
    }
    return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}

$iniUtc = ConvertFrom-LocalToUtc $Inicio
$fimUtc = ConvertFrom-LocalToUtc $Fim
$histUtc = ConvertFrom-LocalToUtc $HistoricoDesde
$agoraUtc = [datetime]::UtcNow
if ($fimUtc -gt $agoraUtc) { $fimUtc = $agoraUtc }
if ($fimUtc -le $iniUtc) { throw 'O fim do período tem de ser posterior ao início.' }
if ($histUtc -gt $iniUtc) { $histUtc = $iniUtc }

# ---------- Autenticação (device code, token só em memória) ----------
function Get-DeviceCodeToken {
    $authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
    $dc = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" -Body @{
        client_id = $ClientId
        scope     = "$EnvironmentUrl/.default"
    }
    Write-Host $dc.message -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
    $interval = [int]$dc.interval
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $tok = Invoke-RestMethod -Method Post -Uri "$authority/token" -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $dc.device_code
            }
            return $tok.access_token
        } catch {
            $code = $null
            try { $code = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { }
            if ($code -eq 'authorization_pending') { continue }
            if ($code -eq 'slow_down') { $interval += 5; continue }
            throw
        }
    }
    throw 'O código de dispositivo expirou antes da autenticação.'
}

$token = Get-DeviceCodeToken
$headers = @{
    Authorization      = "Bearer $token"
    Accept             = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    Prefer             = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue",odata.maxpagesize=5000'
}

function Invoke-DvGet([string]$path) {
    $uri = if ($path -like 'http*') { $path } else { "$apiBase/$path" }
    Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
}
function Get-DvAll([string]$path) {
    $items = [System.Collections.Generic.List[object]]::new()
    $r = Invoke-DvGet $path
    foreach ($x in @($r.value)) { $items.Add($x) }
    while ($r.'@odata.nextLink') {
        $r = Invoke-DvGet $r.'@odata.nextLink'
        foreach ($x in @($r.value)) { $items.Add($x) }
    }
    return , $items
}
function Format-Iso([datetime]$utc) { $utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") }

$avisos = [System.Collections.Generic.List[string]]::new()

# ---------- Metadados e estado da auditoria ----------
Write-Host 'A ler metadados...'
$attrMeta = Invoke-DvGet "EntityDefinitions(LogicalName='systemuser')/Attributes(LogicalName='$Attribute')?`$select=LogicalName,AttributeType,ColumnNumber,IsAuditEnabled"
$colNumber = $attrMeta.ColumnNumber
$auditColuna = $attrMeta.IsAuditEnabled.Value
$auditTabela = (Invoke-DvGet "EntityDefinitions(LogicalName='systemuser')?`$select=IsAuditEnabled").IsAuditEnabled.Value
$auditOrg = $null
try { $auditOrg = (Invoke-DvGet 'organizations?$select=isauditenabled').value[0].isauditenabled } catch { $avisos.Add("Não foi possível ler organization.isauditenabled: " + $_.Exception.Message) }

if ($attrMeta.AttributeType -ne 'Boolean') { $avisos.Add("A coluna $Attribute é do tipo $($attrMeta.AttributeType), não Boolean.") }
if (-not $auditColuna) { $avisos.Add("Auditoria DESLIGADA na coluna ${Attribute}: o histórico pode estar vazio ou incompleto.") }
if (-not $auditTabela) { $avisos.Add('Auditoria DESLIGADA na tabela systemuser.') }
if ($auditOrg -eq $false) { $avisos.Add('Auditoria DESLIGADA na organização.') }

# ---------- Utilizadores ----------
Write-Host 'A ler utilizadores...'
$userFilter = if ($IncluirDesativados) { '' } else { '&$filter=isdisabled eq false' }
$users = Get-DvAll ("systemusers?`$select=systemuserid,fullname,domainname,isdisabled,$Attribute" + $userFilter + '&$orderby=fullname')
Write-Host "  $($users.Count) utilizadores."

# ---------- Auditoria ----------
Write-Host "A ler auditoria de systemuser desde $(Format-Iso $histUtc)..."
$auditFilter = "objecttypecode eq 'systemuser' and operation eq 2 and createdon ge $(Format-Iso $histUtc)"
$audits = Get-DvAll ('audits?$select=auditid,createdon,_objectid_value,_userid_value,action,changedata,attributemask' +
    "&`$filter=$auditFilter&`$orderby=createdon asc")
Write-Host "  $($audits.Count) registos de atualização de systemuser."

function ConvertTo-NullableBool($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [bool]) { return $v }
    $s = ([string]$v).Trim()
    if ($s -match '^(?i)(true|1)$') { return $true }
    if ($s -match '^(?i)(false|0)$') { return $false }
    return $null
}

function Get-ChangeFromChangeData([string]$changedata) {
    if ([string]::IsNullOrWhiteSpace($changedata) -or $changedata -notmatch $Attribute) { return $null }
    try {
        $j = $changedata | ConvertFrom-Json
        $item = @($j.changedAttributes) | Where-Object { $_.logicalName -eq $Attribute } | Select-Object -First 1
        if ($item) {
            return [pscustomobject]@{
                Old   = (ConvertTo-NullableBool $item.oldValue)
                New   = (ConvertTo-NullableBool $item.newValue)
                Fonte = 'changedata'
            }
        }
    } catch { }
    return $null
}

function Get-ChangeFromAuditDetails([string]$auditId) {
    $d = (Invoke-DvGet "audits($auditId)/Microsoft.Dynamics.CRM.RetrieveAuditDetails()").AuditDetail
    $hasOld = ($null -ne $d.OldValue) -and $d.OldValue.PSObject.Properties[$Attribute]
    $hasNew = ($null -ne $d.NewValue) -and $d.NewValue.PSObject.Properties[$Attribute]
    if (-not $hasOld -and -not $hasNew) { return $null }
    [pscustomobject]@{
        Old   = $(if ($hasOld) { ConvertTo-NullableBool $d.OldValue.$Attribute } else { $null })
        New   = $(if ($hasNew) { ConvertTo-NullableBool $d.NewValue.$Attribute } else { $null })
        Fonte = 'RetrieveAuditDetails'
    }
}

$maskPattern = if ($null -ne $colNumber) { "(^|,)$colNumber(,|$)" } else { $null }
$userNames = @{}
foreach ($u in $users) { $userNames[[string]$u.systemuserid] = $u.fullname }

$events = [System.Collections.Generic.List[object]]::new()
$fallbacks = 0
foreach ($a in $audits) {
    $change = Get-ChangeFromChangeData $a.changedata
    if (-not $change) {
        $mask = [string]$a.attributemask
        $mentions = ($a.changedata -match $Attribute) -or ($maskPattern -and $mask -match $maskPattern)
        if (-not $mentions) { continue }
        $change = Get-ChangeFromAuditDetails $a.auditid
        $fallbacks++
        if (-not $change) { continue }
    }
    $created = ConvertTo-UtcDate $a.createdon
    $events.Add([pscustomobject]@{
        AuditId      = [string]$a.auditid
        UserId       = [string]$a._objectid_value
        CreatedOnUtc = $created
        Old          = $change.Old
        New          = $change.New
        AlteradoPor  = $a.'_userid_value@OData.Community.Display.V1.FormattedValue'
        Fonte        = $change.Fonte
    })
}
Write-Host "  $($events.Count) alterações de $Attribute ($fallbacks lidas por RetrieveAuditDetails)."

# ---------- Cálculo ----------
function Format-Estado($v) { if ($null -eq $v) { 'sem valor' } elseif ($v) { 'true' } else { 'false' } }

$byUser = @{}
foreach ($e in $events) {
    if (-not $byUser.ContainsKey($e.UserId)) { $byUser[$e.UserId] = [System.Collections.Generic.List[object]]::new() }
    $byUser[$e.UserId].Add($e)
}
$semUtilizador = @($byUser.Keys | Where-Object { -not $userNames.ContainsKey($_) }).Count
if ($semUtilizador -gt 0) { $avisos.Add("$semUtilizador utilizador(es) com alterações auditadas não entraram no resumo (desativados ou fora do filtro). Use -IncluirDesativados se precisar deles.") }

$resumo = [System.Collections.Generic.List[object]]::new()
$intervalos = [System.Collections.Generic.List[object]]::new()

foreach ($u in $users) {
    $id = [string]$u.systemuserid
    $ev = if ($byUser.ContainsKey($id)) { @($byUser[$id] | Sort-Object CreatedOnUtc) } else { @() }
    $antes = @($ev | Where-Object { $_.CreatedOnUtc -le $iniUtc })
    $dentro = @($ev | Where-Object { $_.CreatedOnUtc -gt $iniUtc -and $_.CreatedOnUtc -lt $fimUtc })
    $depois = @($ev | Where-Object { $_.CreatedOnUtc -ge $fimUtc })
    $atual = ConvertTo-NullableBool $u.$Attribute

    if ($antes.Count -gt 0) { $estado = $antes[-1].New; $origem = 'última alteração antes do início' }
    elseif ($dentro.Count -gt 0) { $estado = $dentro[0].Old; $origem = 'valor antigo da 1ª alteração no período' }
    elseif ($depois.Count -gt 0) { $estado = $depois[0].Old; $origem = 'valor antigo da 1ª alteração após o fim' }
    else { $estado = $atual; $origem = 'valor atual (sem alterações auditadas)' }
    $estadoInicial = $estado

    $min = @{ 'true' = 0.0; 'false' = 0.0; 'sem valor' = 0.0 }
    $alteracoes = 0
    $cursor = $iniUtc
    $pontos = @($dentro) + @([pscustomobject]@{ CreatedOnUtc = $fimUtc; Fim = $true })
    foreach ($p in $pontos) {
        $dur = ($p.CreatedOnUtc - $cursor).TotalMinutes
        if ($dur -gt 0) {
            $k = Format-Estado $estado
            $min[$k] += $dur
            $intervalos.Add([pscustomobject]@{
                Utilizador = $u.fullname
                DomainName = $u.domainname
                Inicio     = ConvertTo-Local $cursor
                Fim        = ConvertTo-Local $p.CreatedOnUtc
                Estado     = $k
                Minutos    = [math]::Round($dur, 1)
            })
        }
        if (-not $p.PSObject.Properties['Fim']) {
            if ($p.New -ne $estado) { $alteracoes++ }
            $estado = $p.New
        }
        $cursor = $p.CreatedOnUtc
    }

    $obs = ''
    if ($depois.Count -eq 0 -and $estado -ne $atual) {
        $obs = "Estado reconstruído no fim ($(Format-Estado $estado)) difere do valor atual ($(Format-Estado $atual)): possível lacuna de auditoria."
    } elseif ($depois.Count -gt 0 -and $depois[0].Old -ne $estado) {
        $obs = 'Valor antigo da alteração seguinte não bate com o estado reconstruído: possível lacuna de auditoria.'
    }

    $total = $min['true'] + $min['false'] + $min['sem valor']
    $resumo.Add([pscustomobject]@{
        Utilizador          = $u.fullname
        DomainName          = $u.domainname
        SystemUserId        = $id
        EstadoInicial       = Format-Estado $estadoInicial
        OrigemEstadoInicial = $origem
        EstadoAtual         = Format-Estado $atual
        MinutosTrue         = [math]::Round($min['true'], 0)
        HorasTrue           = [math]::Round($min['true'] / 60, 2)
        MinutosFalse        = [math]::Round($min['false'], 0)
        HorasFalse          = [math]::Round($min['false'] / 60, 2)
        MinutosSemValor     = [math]::Round($min['sem valor'], 0)
        PctTrue             = $(if ($total -gt 0) { [math]::Round($min['true'] / $total, 4) } else { 0 })
        Alteracoes          = $alteracoes
        Observacao          = $obs
    })
}

$eventosOut = foreach ($e in ($events | Sort-Object CreatedOnUtc)) {
    [pscustomobject]@{
        DataHora     = ConvertTo-Local $e.CreatedOnUtc
        DataHoraUtc  = $e.CreatedOnUtc
        Utilizador   = $(if ($userNames.ContainsKey($e.UserId)) { $userNames[$e.UserId] } else { $e.UserId })
        ValorAntigo  = Format-Estado $e.Old
        ValorNovo    = Format-Estado $e.New
        AlteradoPor  = $e.AlteradoPor
        Fonte        = $e.Fonte
        AuditId      = $e.AuditId
    }
}

$parametros = @(
    [pscustomobject]@{ Parametro = 'Ambiente'; Valor = $EnvironmentUrl }
    [pscustomobject]@{ Parametro = 'Fuso'; Valor = $TimeZoneId }
    [pscustomobject]@{ Parametro = 'Início (local)'; Valor = (ConvertTo-Local $iniUtc).ToString('yyyy-MM-dd HH:mm') }
    [pscustomobject]@{ Parametro = 'Fim (local)'; Valor = (ConvertTo-Local $fimUtc).ToString('yyyy-MM-dd HH:mm') }
    [pscustomobject]@{ Parametro = 'Início / fim (UTC)'; Valor = "$(Format-Iso $iniUtc) / $(Format-Iso $fimUtc)" }
    [pscustomobject]@{ Parametro = 'Auditoria lida desde (UTC)'; Valor = Format-Iso $histUtc }
    [pscustomobject]@{ Parametro = 'Auditoria organização / tabela / coluna'; Valor = "$auditOrg / $auditTabela / $auditColuna" }
    [pscustomobject]@{ Parametro = 'Registos de auditoria lidos'; Valor = $audits.Count }
    [pscustomobject]@{ Parametro = "Alterações de $Attribute"; Valor = $events.Count }
    [pscustomobject]@{ Parametro = 'Gerado em (UTC)'; Valor = Format-Iso $agoraUtc }
)
$parametros += foreach ($a in $avisos) { [pscustomobject]@{ Parametro = 'AVISO'; Valor = $a } }
foreach ($a in $avisos) { Write-Warning $a }

# ---------- Exportação ----------
function Export-Xlsx([string]$path, [System.Collections.Specialized.OrderedDictionary]$sheets) {
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible = $false
    $xl.DisplayAlerts = $false
    $prev = [int]$xl.SheetsInNewWorkbook
    try {
        $xl.SheetsInNewWorkbook = [int]$sheets.Count
        $wb = $xl.Workbooks.Add()
        $xl.SheetsInNewWorkbook = $prev
        $i = 1
        foreach ($name in $sheets.Keys) {
            $ws = $wb.Worksheets.Item($i)
            $ws.Name = $name
            $rows = @($sheets[$name])
            if ($rows.Count -gt 0) {
                $cols = @($rows[0].PSObject.Properties.Name)
                $arr = New-Object 'object[,]' ($rows.Count + 1), $cols.Count
                $dateCols = @{}
                for ($c = 0; $c -lt $cols.Count; $c++) { $arr[0, $c] = $cols[$c] }
                for ($r = 0; $r -lt $rows.Count; $r++) {
                    for ($c = 0; $c -lt $cols.Count; $c++) {
                        $v = $rows[$r].($cols[$c])
                        if ($v -is [datetime]) { $v = $v.ToOADate(); $dateCols[$c] = $true }
                        $arr[($r + 1), $c] = $v
                    }
                }
                $range = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item($rows.Count + 1, $cols.Count))
                $range.Value2 = $arr
                foreach ($c in $dateCols.Keys) { $ws.Columns.Item($c + 1).NumberFormat = 'yyyy-mm-dd hh:mm:ss' }
                $ws.Rows.Item(1).Font.Bold = $true
                [void]$range.AutoFilter()
                [void]$ws.UsedRange.Columns.AutoFit()
            }
            $i++
        }
        $wb.SaveAs($path, 51)
        $wb.Close($false)
    } finally {
        $xl.Quit()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl)
    }
}

$sheets = [ordered]@{
    Resumo     = $resumo
    Intervalos = $intervalos
    Eventos    = @($eventosOut)
    Parametros = $parametros
}

$OutputPath = [IO.Path]::GetFullPath($OutputPath)
try {
    Export-Xlsx $OutputPath $sheets
    Write-Host "Excel gerado: $OutputPath" -ForegroundColor Green
} catch {
    Write-Warning "Não foi possível gerar o .xlsx pelo Excel ($($_.Exception.Message)). A gravar CSVs."
    $base = [IO.Path]::Combine([IO.Path]::GetDirectoryName($OutputPath), [IO.Path]::GetFileNameWithoutExtension($OutputPath))
    foreach ($name in $sheets.Keys) {
        @($sheets[$name]) | Export-Csv -Path "$base-$name.csv" -Delimiter ';' -Encoding utf8BOM -NoTypeInformation
        Write-Host "CSV gerado: $base-$name.csv" -ForegroundColor Green
    }
}

$token = $null
$headers = $null
